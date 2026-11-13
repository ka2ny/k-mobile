import pathlib
import subprocess
import sys
import unittest

RUNNER = pathlib.Path(__file__).with_name('run_bounded.py')


class BoundedCommandTests(unittest.TestCase):
    def test_preserves_failure_and_output(self):
        result = subprocess.run([sys.executable, str(RUNNER), '--seconds', '3', '--', sys.executable,
                                 '-c', 'print("diagnostic"); raise SystemExit(7)'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)
        self.assertIn('diagnostic', result.stdout)

    def test_timeout_returns_publishable_failure(self):
        result = subprocess.run([sys.executable, str(RUNNER), '--seconds', '0.1', '--', sys.executable,
                                 '-c', 'import time; time.sleep(30)'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 124)
        self.assertIn('stopping its process group', result.stderr)
