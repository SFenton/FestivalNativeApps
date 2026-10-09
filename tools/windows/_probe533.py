"""Temporary CI probe for #533 bands-empty (removed before finishing)."""
import os, subprocess, sys, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "windows"))
import journey_exe  # noqa: E402

PS = r'''
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$A = [System.Windows.Automation.AutomationElement]
$root = $A::RootElement
$win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, (New-Object System.Windows.Automation.PropertyCondition($A::ProcessIdProperty, PIDX)))
function Find($id) { $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, $id))) }
$sv = Find 'fst.player.available'
$sp = $sv.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
function Report($label) {
  $c = $sp.Current
  $line = "$label -> pct=$([math]::Round($c.VerticalScrollPercent,2)) view=$([math]::Round($c.VerticalViewSize,3))"
  foreach ($k in 'fst.player.bands','fst.player.bands.empty.duos','fst.player.bands.empty.trios','fst.player.bands.empty.quads') {
    $e = Find $k; if ($e) { $r = $e.Current.BoundingRectangle; $line += " | $($k.Split('.')[-1])=$([int]$r.Y),$([int]$r.Height)" } else { $line += " | $($k.Split('.')[-1])=missing" }
  }
  $line
}
Report 'start'
foreach ($p in 86,88,90,92,94,96,98,100) {
  $sp.SetScrollPercent(-1, $p); Start-Sleep -Milliseconds 300; Report "set $p (300ms)"; Start-Sleep -Milliseconds 1200; Report "set $p (1.5s)"
}
$sp.SetScrollPercent(-1, 85); Start-Sleep -Milliseconds 800; Report 'reset 85'
for ($i = 0; $i -lt 8; $i++) { $sp.ScrollVertical([System.Windows.Automation.ScrollAmount]::SmallIncrement); Start-Sleep -Milliseconds 400; Report "small $i" }
for ($i = 0; $i -lt 4; $i++) { $sp.ScrollVertical([System.Windows.Automation.ScrollAmount]::LargeIncrement); Start-Sleep -Milliseconds 600; Report "large $i" }
'''


def uiwin(*args):
    r = subprocess.run([sys.executable, str(REPO / "tools" / "windows" / "uiwin.py"), *args], capture_output=True, text=True, encoding="utf-8")
    print(f"$ uiwin {' '.join(args)[:200]}\n{r.stdout[-600:]}\n{r.stderr[-600:]}", flush=True)
    return r


def probe(pid, label):
    script = Path(tempfile.gettempdir()) / "probe533.ps1"
    script.write_text(PS.replace("PIDX", str(pid)), encoding="utf-8")
    r = subprocess.run(["powershell", "-NoProfile", "-File", str(script)], capture_output=True, text=True)
    print(f"--- probe {label}\n{r.stdout}\n{r.stderr}", flush=True)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    mock = subprocess.Popen([sys.executable, str(REPO / "tools" / "mock_service.py"), "--port", "18533"])
    time.sleep(4)
    settings = Path(tempfile.mkdtemp()) / "settings.json"
    r = uiwin("launch", str(journey_exe.DEBUG_EXE), "--arg=--base-url", "--arg=http://127.0.0.1:18533/", "--arg=--settings-path",
              f"--arg={settings}", "--preset", "portrait-tablet", "--arg=--route", "--arg=/player/fixture-player-2", "--arg=--anonymous")
    pid = next(int(l.split(":")[1].strip().rstrip(",")) for l in r.stdout.splitlines() if '"pid"' in l)
    uiwin("drive", "--pid", str(pid), "--steps", "waitfor:id=fst.player.overview@15; reveal:id=fst.player.bands@10; reveal:id=fst.player.bands.empty.duos@15")
    time.sleep(2)
    probe(pid, "steps")
    uiwin("drive", "--pid", str(pid), "--steps", f"shot:{out / 'probe-end.png'}")
    uiwin("close", "--pid", str(pid))
    mock.terminate()


main()
