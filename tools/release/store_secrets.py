#!/usr/bin/env python3
"""Upload release signing/store credentials to the ``store-release`` GitHub environment.

Builds, signing, uploads and store calls run only in GitHub Actions; their
credentials live only in the master-only ``store-release`` environment of
``SFenton/FestivalNativeApps``. This tool is the one supported way to put them
there. Values reach ``gh secret set`` on stdin, never on a command line, and the
tool never prints them::

    store_secrets.py status
    store_secrets.py asc --key-id ABC123DEFG --issuer-id <uuid> --p8 AuthKey_ABC123DEFG.p8
    store_secrets.py ios-p12 --p12 dist.p12 --password-file dist.pw
    store_secrets.py ios-dev-p12 --p12 dev.p12 --password-file dev.pw   # one persistent CI Apple Development identity
    store_secrets.py msstore --tenant-id <uuid> --client-id <uuid> \\
        --client-secret-file secret.txt --seller-id 123456 --app-id 9ABCDEFGHIJK
    store_secrets.py android-upload-key --generate ~/.config/fst-release/android   # new Play upload key, then upload
    store_secrets.py android-upload-key --keystore upload.p12 --alias upload --password-file upload.pw
    store_secrets.py play --service-account-json play-ci.json    # Play Developer API service account

``android-upload-key --generate DIR`` creates a PKCS#12 upload keystore and its password file in ``DIR`` (mode 600,
never printed): keep that folder backed up. Play App Signing holds the app signing key; a lost upload key can be
reset in Play Console, but only with the upload certificate (``DIR/upload-certificate.pem``).

``status`` prints ``{"groups": {name: {"configured": bool, "missing": [...]}}}``.
Exit codes: 0 ok, 2 invalid input, 1 ``gh`` failure.
Documentation: .agents/workflow/release-machine.md.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence, Tuple

REPO = "SFenton/FestivalNativeApps"
ENVIRONMENT = "store-release"

GROUPS: Dict[str, List[str]] = {
    "asc": ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"],
    "ios_p12": ["IOS_DIST_P12_BASE64", "IOS_DIST_P12_PASSWORD"],
    "ios_dev_p12": ["IOS_DEV_P12_BASE64", "IOS_DEV_P12_PASSWORD"],
    "msstore": ["MSSTORE_TENANT_ID", "MSSTORE_CLIENT_ID", "MSSTORE_CLIENT_SECRET",
                "MSSTORE_SELLER_ID", "MSSTORE_APP_ID"],
    "android_upload_key": ["ANDROID_UPLOAD_KEYSTORE_BASE64", "ANDROID_UPLOAD_KEYSTORE_PASSWORD",
                           "ANDROID_UPLOAD_KEY_ALIAS"],
    "play": ["PLAY_SERVICE_ACCOUNT_JSON"],
}

UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
ASC_KEY_ID_RE = re.compile(r"^[A-Z0-9]{10}$")
SELLER_RE = re.compile(r"^[0-9]{1,20}$")
STORE_ID_RE = re.compile(r"^9[A-Z0-9]{11}$")

Runner = Callable[[Sequence[str], Optional[bytes]], "subprocess.CompletedProcess[bytes]"]


class InputError(ValueError):
    """Rejected credential input (exit 2)."""


# region gh access


def run_gh(argv: Sequence[str], stdin: Optional[bytes] = None) -> "subprocess.CompletedProcess[bytes]":
    """Run ``gh`` with ``argv``; ``stdin`` carries any secret value."""
    return subprocess.run(["gh", *argv], input=stdin, capture_output=True, check=False)


def set_secret(name: str, value: str, runner: Runner, repo: str = REPO) -> None:
    """Set one environment secret, passing ``value`` on stdin.

    Raises:
        RuntimeError: ``gh`` failed (its stderr is included; it never echoes the value).
    """
    if not value:
        raise InputError("%s is empty" % name)
    result = runner(["secret", "set", name, "--env", ENVIRONMENT, "-R", repo], value.encode("utf-8"))
    if result.returncode != 0:
        raise RuntimeError("gh secret set %s failed: %s" % (name, result.stderr.decode("utf-8", "replace").strip()))


def configured_names(runner: Runner, repo: str = REPO) -> List[str]:
    """Return the secret names present in the environment."""
    result = runner(["secret", "list", "--env", ENVIRONMENT, "-R", repo, "--json", "name"], None)
    if result.returncode != 0:
        raise RuntimeError("gh secret list failed: %s" % result.stderr.decode("utf-8", "replace").strip())
    return sorted(item["name"] for item in json.loads(result.stdout.decode("utf-8") or "[]"))


def status(runner: Runner, repo: str = REPO) -> Dict[str, Dict[str, object]]:
    """Report which credential groups are complete."""
    present = set(configured_names(runner, repo))
    return {
        group: {"configured": all(n in present for n in names), "missing": [n for n in names if n not in present]}
        for group, names in GROUPS.items()
    }


# endregion

# region Validation


def read_text(path: str) -> str:
    """Read a credential file, stripping one trailing newline only."""
    text = Path(path).read_text(encoding="utf-8")
    return text[:-1] if text.endswith("\n") else text


def validate_asc(key_id: str, issuer_id: str, p8: str) -> None:
    """Validate an App Store Connect API key triple."""
    if not ASC_KEY_ID_RE.match(key_id):
        raise InputError("ASC key id must be 10 upper-case letters/digits")
    if not UUID_RE.match(issuer_id):
        raise InputError("ASC issuer id must be a UUID")
    if "-----BEGIN PRIVATE KEY-----" not in p8 or "-----END PRIVATE KEY-----" not in p8:
        raise InputError("ASC key file is not a PKCS#8 .p8 private key")


def p12_subjects(p12: bytes, password: str, openssl: Optional[str] = None) -> Optional[List[str]]:
    """Return the certificate subjects in a PKCS#12 file (``None`` when openssl is unavailable).

    Raises:
        InputError: openssl cannot open the file with ``password``.
    """
    openssl = openssl or shutil.which("openssl")
    if not openssl:
        return None
    for extra in ([], ["-legacy"]):
        result = _openssl_p12(openssl, extra, p12, password)
        if result is not None:
            return result
    raise InputError("cannot open the .p12 with the given password")


def _openssl_p12(openssl: str, extra: List[str], p12: bytes, password: str) -> Optional[List[str]]:
    """Run ``openssl pkcs12`` on ``p12`` via a private temp file; ``None`` on failure."""
    fd, path = tempfile.mkstemp(suffix=".p12")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(p12)
        env = dict(os.environ, FST_P12_PASSWORD=password)
        result = subprocess.run(
            [openssl, "pkcs12", *extra, "-in", path, "-nokeys", "-passin", "env:FST_P12_PASSWORD"],
            capture_output=True, check=False, env=env,
        )
    finally:
        os.unlink(path)
    if result.returncode != 0:
        return None
    return [line.split("=", 1)[1].strip() if "=" in line else line
            for line in result.stdout.decode("utf-8", "replace").splitlines() if line.startswith("subject=")]


def validate_p12_subjects(subjects: Optional[List[str]], kind: str = "Apple Distribution") -> None:
    """Require exactly one certificate and that it is a ``kind`` identity."""
    if subjects is None:
        return
    if len(subjects) != 1:
        raise InputError("the .p12 must hold exactly one certificate (found %d)" % len(subjects))
    if kind not in subjects[0]:
        raise InputError("the .p12 certificate is not an %s identity" % kind)


def validate_msstore(tenant_id: str, client_id: str, secret: str, seller_id: str, app_id: str) -> None:
    """Validate Partner Center / Entra identifiers."""
    if not UUID_RE.match(tenant_id) or not UUID_RE.match(client_id):
        raise InputError("tenant and client ids must be UUIDs")
    if not secret.strip():
        raise InputError("client secret is empty")
    if not SELLER_RE.match(seller_id):
        raise InputError("seller id must be numeric")
    if not STORE_ID_RE.match(app_id):
        raise InputError("app id must be the 12-character Store ID (9…)")


def find_keytool(explicit: Optional[str] = None) -> str:
    """``keytool`` from ``--keytool``, ``PATH`` or ``$JAVA_HOME/bin``."""
    for candidate in (explicit, shutil.which("keytool"),
                      os.path.join(os.environ.get("JAVA_HOME", ""), "bin", "keytool") if os.environ.get("JAVA_HOME") else None):
        if candidate and os.path.exists(candidate):
            return candidate
    raise InputError("keytool not found: install a JDK, set JAVA_HOME or pass --keytool")


def keystore_aliases(keytool: str, keystore: Path, password: str) -> List[str]:
    """Aliases in a keystore (the password is passed through the environment).

    Raises:
        InputError: keytool cannot open the keystore with ``password``.
    """
    env = dict(os.environ, FST_KS_PASSWORD=password)
    result = subprocess.run([keytool, "-list", "-keystore", str(keystore), "-storepass:env", "FST_KS_PASSWORD"],
                            capture_output=True, check=False, env=env)
    if result.returncode != 0:
        raise InputError("cannot open the keystore with the given password")
    return [line.split(",", 1)[0].strip() for line in result.stdout.decode("utf-8", "replace").splitlines()
            if ", PrivateKeyEntry" in line]


def generate_upload_key(keytool: str, directory: Path, alias: str = "upload") -> Tuple[Path, str]:
    """Create ``upload.p12`` (RSA 4096, 30 years), its password file and certificate in ``directory`` (mode 600).

    Returns:
        The keystore path and its password.

    Raises:
        InputError: the keystore already exists (never overwritten) or keytool failed.
    """
    directory.mkdir(parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    keystore, pw_file, cert = directory / "upload.p12", directory / "upload.pw", directory / "upload-certificate.pem"
    if keystore.exists():
        raise InputError(f"{keystore} already exists; upload it with --keystore instead")
    password = base64.urlsafe_b64encode(os.urandom(24)).decode("ascii")
    env = dict(os.environ, FST_KS_PASSWORD=password)
    made = subprocess.run([keytool, "-genkeypair", "-keystore", str(keystore), "-storetype", "PKCS12",
                           "-alias", alias, "-keyalg", "RSA", "-keysize", "4096", "-validity", "10950",
                           "-dname", "CN=Festival Score Tracker Upload, O=SFenton",
                           "-storepass:env", "FST_KS_PASSWORD", "-keypass:env", "FST_KS_PASSWORD"],
                          capture_output=True, check=False, env=env)
    if made.returncode != 0:
        raise InputError("keytool could not create the keystore")
    exported = subprocess.run([keytool, "-exportcert", "-rfc", "-keystore", str(keystore), "-alias", alias,
                               "-storepass:env", "FST_KS_PASSWORD", "-file", str(cert)],
                              capture_output=True, check=False, env=env)
    pw_file.write_text(password + "\n", encoding="utf-8")
    for path in (keystore, pw_file, cert):
        if path.exists():
            os.chmod(path, 0o600)
    if exported.returncode != 0:
        raise InputError("keytool could not export the upload certificate")
    return keystore, password


def validate_service_account(raw: str) -> None:
    """A Google service-account key (the Play Developer API credential)."""
    try:
        data = json.loads(raw)
    except ValueError as err:
        raise InputError("not a JSON file") from err
    if not isinstance(data, dict) or data.get("type") != "service_account":
        raise InputError("not a service-account key (type must be service_account)")
    if not str(data.get("client_email", "")).endswith(".iam.gserviceaccount.com"):
        raise InputError("client_email is not a service account")
    if "BEGIN PRIVATE KEY" not in str(data.get("private_key", "")):
        raise InputError("private_key is missing")


# endregion

# region CLI


def main(argv: Optional[Sequence[str]] = None, runner: Runner = run_gh,
         subjects_fn: Callable[[bytes, str], Optional[List[str]]] = p12_subjects) -> int:
    """Command-line entry point; see the module docstring."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--repo", default=REPO)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    asc = sub.add_parser("asc")
    asc.add_argument("--key-id", required=True)
    asc.add_argument("--issuer-id", required=True)
    asc.add_argument("--p8", required=True)
    p12 = sub.add_parser("ios-p12")
    p12.add_argument("--p12", required=True)
    p12.add_argument("--password-file", required=True)
    dev = sub.add_parser("ios-dev-p12")
    dev.add_argument("--p12", required=True)
    dev.add_argument("--password-file", required=True)
    ms = sub.add_parser("msstore")
    ms.add_argument("--tenant-id", required=True)
    ms.add_argument("--client-id", required=True)
    ms.add_argument("--client-secret-file", required=True)
    ms.add_argument("--seller-id", required=True)
    ms.add_argument("--app-id", required=True)
    ak = sub.add_parser("android-upload-key")
    ak.add_argument("--generate", metavar="DIR", help="create a new upload keystore in DIR, then upload it")
    ak.add_argument("--keystore", help="an existing PKCS#12/JKS upload keystore")
    ak.add_argument("--alias", default="upload")
    ak.add_argument("--password-file", help="keystore password (also the key password)")
    ak.add_argument("--keytool")
    play = sub.add_parser("play")
    play.add_argument("--service-account-json", required=True)
    args = parser.parse_args(argv)

    try:
        if args.command == "status":
            print(json.dumps({"environment": ENVIRONMENT, "groups": status(runner, args.repo)}, sort_keys=True))
            return 0
        if args.command == "asc":
            p8 = read_text(args.p8)
            validate_asc(args.key_id, args.issuer_id, p8)
            values = {"ASC_KEY_ID": args.key_id, "ASC_ISSUER_ID": args.issuer_id, "ASC_PRIVATE_KEY": p8}
        elif args.command in ("ios-p12", "ios-dev-p12"):
            dev = args.command == "ios-dev-p12"
            data = Path(args.p12).read_bytes()
            password = read_text(args.password_file)
            validate_p12_subjects(subjects_fn(data, password), "Apple Development" if dev else "Apple Distribution")
            prefix = "IOS_DEV_P12" if dev else "IOS_DIST_P12"
            values = {prefix + "_BASE64": base64.b64encode(data).decode("ascii"), prefix + "_PASSWORD": password}
        elif args.command == "android-upload-key":
            keytool = find_keytool(args.keytool)
            if args.generate:
                keystore, password = generate_upload_key(keytool, Path(os.path.expanduser(args.generate)), args.alias)
            elif args.keystore and args.password_file:
                keystore, password = Path(args.keystore), read_text(args.password_file)
            else:
                raise InputError("pass --generate DIR, or --keystore and --password-file")
            if args.alias not in keystore_aliases(keytool, keystore, password):
                raise InputError(f"the keystore has no private key under alias {args.alias!r}")
            values = {"ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(keystore.read_bytes()).decode("ascii"),
                      "ANDROID_UPLOAD_KEYSTORE_PASSWORD": password, "ANDROID_UPLOAD_KEY_ALIAS": args.alias}
        elif args.command == "play":
            raw = read_text(args.service_account_json)
            validate_service_account(raw)
            values = {"PLAY_SERVICE_ACCOUNT_JSON": raw}
        else:
            secret = read_text(args.client_secret_file)
            validate_msstore(args.tenant_id, args.client_id, secret, args.seller_id, args.app_id)
            values = {"MSSTORE_TENANT_ID": args.tenant_id, "MSSTORE_CLIENT_ID": args.client_id,
                      "MSSTORE_CLIENT_SECRET": secret, "MSSTORE_SELLER_ID": args.seller_id,
                      "MSSTORE_APP_ID": args.app_id}
        for name, value in values.items():
            set_secret(name, value, runner, args.repo)
    except (InputError, OSError) as err:
        print(json.dumps({"error": str(err)}), file=sys.stderr)
        return 2
    except RuntimeError as err:
        print(json.dumps({"error": str(err)}), file=sys.stderr)
        return 1
    print(json.dumps({"set": sorted(values), "environment": ENVIRONMENT}))
    return 0


# endregion

if __name__ == "__main__":
    sys.exit(main())
