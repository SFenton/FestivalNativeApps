"""Retry classification for the CI Gradle wrapper (#697, #702).

Run: ``python -m unittest discover -s tools/android/tests`` from the repo root.
"""

import unittest

from tools.android.ci_gradle import (
    REFRESH_FLAG,
    SERVER_RETRY_DELAYS_SECONDS,
    classify_download_failure,
    is_transient_dependency_failure,
    run_with_retry,
)

# The failure from releases/2611.09 android-device run 43017000822.
ARTIFACT_404 = [
    "> Could not resolve all files for configuration ':app:debugRuntimeClasspath'.\n",
    "   > Failed to transform listenablefuture-1.0.jar (com.google.guava:listenablefuture:1.0) to match attributes\n",
    "      > Could not find listenablefuture-1.0.jar (com.google.guava:listenablefuture:1.0).\n",
    "        Searched in the following locations:\n",
    "            https://repo.maven.apache.org/maven2/com/google/guava/listenablefuture/1.0/listenablefuture-1.0.jar\n",
]
HTTP_ERROR = [
    "   > Could not resolve androidx.core:core:1.13.1.\n",
    "      > Could not GET 'https://dl.google.com/dl/android/maven2/androidx/core/core/1.13.1/core-1.13.1.pom'.\n",
    "         > Received status code 502 from server: Bad Gateway\n",
]
# The failures from releases/2611.16 android-fold run 44519886675 (#702): attempt 1, then attempt 2
# with --refresh-dependencies re-requesting cached build-script dependencies.
RATE_LIMITED_ARTIFACT = [
    "> Could not resolve all files for configuration ':app:debugRuntimeClasspath'.\n",
    "      > Could not download listenablefuture-1.0.jar (com.google.guava:listenablefuture:1.0)\n",
    "         > Could not get resource 'https://repo.maven.apache.org/maven2/com/google/guava/listenablefuture/1.0/listenablefuture-1.0.jar'.\n",
    "            > Could not GET 'https://repo.maven.apache.org/maven2/com/google/guava/listenablefuture/1.0/listenablefuture-1.0.jar'. Received status code 429 from server: Too Many Requests\n",
]
RATE_LIMITED_CLASSPATH = [
    "> Could not resolve all artifacts for configuration 'classpath'.\n",
    "   > Could not resolve org.jetbrains.kotlin:kotlin-stdlib:2.0.21.\n",
    "         > Could not get resource 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/2.0.21/kotlin-stdlib-2.0.21.pom'.\n",
    "            > Could not GET 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/2.0.21/kotlin-stdlib-2.0.21.pom'. Received status code 429 from server: Too Many Requests\n",
]
COMPILE_ERROR = [
    "e: file:///android/app/src/main/java/Foo.kt:3:5 Unresolved reference 'bar'.\n",
    "> Task :app:compileDebugKotlin FAILED\n",
]
UNKNOWN_MODULE = [
    "> Could not resolve all files for configuration ':app:debugRuntimeClasspath'.\n",
    "   > Could not find com.example:nope:9.9.\n",
]


class ClassificationTests(unittest.TestCase):
    """Only repository download failures are retried."""

    def test_artifact_404_is_transient(self):
        self.assertTrue(is_transient_dependency_failure(ARTIFACT_404))

    def test_http_error_is_transient(self):
        self.assertTrue(is_transient_dependency_failure(HTTP_ERROR))

    def test_rate_limit_is_a_server_error_not_a_cached_miss(self):
        failure = classify_download_failure(RATE_LIMITED_ARTIFACT)
        self.assertIsNotNone(failure)
        self.assertTrue(failure.server_error)
        self.assertFalse(failure.cached_miss)

    def test_artifact_404_is_a_cached_miss(self):
        failure = classify_download_failure(ARTIFACT_404)
        self.assertTrue(failure.cached_miss)
        self.assertFalse(failure.server_error)

    def test_compile_error_is_not_transient(self):
        self.assertFalse(is_transient_dependency_failure(COMPILE_ERROR))

    def test_unknown_module_is_not_transient(self):
        self.assertFalse(is_transient_dependency_failure(UNKNOWN_MODULE))


class RetryTests(unittest.TestCase):
    """Retries refresh Gradle's cached miss and stop at the first real failure."""

    def run_script(self, results, attempts=3):
        calls, sleeps = [], []

        def run(argv):
            calls.append(list(argv))
            return results[len(calls) - 1]

        code = run_with_retry([":app:assembleDebug", "--no-daemon"], run, sleeps.append, attempts, lambda: 7.0)
        return code, calls, sleeps

    def test_download_failure_is_retried_with_refresh(self):
        code, calls, sleeps = self.run_script([(1, ARTIFACT_404), (0, [])])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 2)
        self.assertNotIn(REFRESH_FLAG, calls[0])
        self.assertEqual(calls[1][-1], REFRESH_FLAG)
        self.assertIn(":app:assembleDebug", calls[1])
        self.assertEqual(len(sleeps), 1)

    def test_success_runs_once(self):
        code, calls, sleeps = self.run_script([(0, [])])
        self.assertEqual((code, len(calls), sleeps), (0, 1, []))

    def test_build_failure_is_not_retried(self):
        code, calls, sleeps = self.run_script([(1, COMPILE_ERROR), (0, [])])
        self.assertEqual((code, len(calls), sleeps), (1, 1, []))

    def test_persistent_download_failure_gives_up_after_the_last_attempt(self):
        code, calls, sleeps = self.run_script([(1, ARTIFACT_404)] * 3)
        self.assertEqual((code, len(calls), len(sleeps)), (1, 3, 2))
        self.assertEqual(calls[2].count(REFRESH_FLAG), 1)

    def test_rate_limit_retries_keep_the_cache_and_back_off_longer(self):
        code, calls, sleeps = self.run_script([(1, RATE_LIMITED_ARTIFACT), (1, RATE_LIMITED_CLASSPATH), (0, [])])
        self.assertEqual((code, len(calls)), (0, 3))
        self.assertTrue(all(REFRESH_FLAG not in call for call in calls))
        self.assertEqual(sleeps, [SERVER_RETRY_DELAYS_SECONDS[0] + 7.0, SERVER_RETRY_DELAYS_SECONDS[1] + 7.0])
        self.assertGreater(sleeps[0], 60)

    def test_404_short_backoff_has_no_jitter(self):
        _, _, sleeps = self.run_script([(1, ARTIFACT_404), (0, [])])
        self.assertEqual(sleeps, [30.0])

    def test_refresh_stays_on_after_a_cached_miss(self):
        code, calls, sleeps = self.run_script([(1, ARTIFACT_404), (1, RATE_LIMITED_CLASSPATH), (0, [])])
        self.assertEqual(code, 0)
        self.assertNotIn(REFRESH_FLAG, calls[0])
        self.assertEqual(calls[1].count(REFRESH_FLAG), 1)
        self.assertEqual(calls[2].count(REFRESH_FLAG), 1)
        self.assertEqual(sleeps[1], SERVER_RETRY_DELAYS_SECONDS[1] + 7.0)

    def test_unknown_module_after_rate_limit_stops(self):
        code, calls, _ = self.run_script([(1, RATE_LIMITED_ARTIFACT), (1, UNKNOWN_MODULE), (0, [])])
        self.assertEqual((code, len(calls)), (1, 2))


if __name__ == "__main__":
    unittest.main()
