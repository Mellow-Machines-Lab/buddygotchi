"""The tests' runner's generator refuses too few tests: a test file gone
missing, or a parse that stopped finding them, fails the build."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

GENERATOR = Path(__file__).resolve().parents[3] / "app" / "tools" / "gen-test-runner.py"


class TooFewTests(unittest.TestCase):
    def test_under_the_floor_it_refuses(self) -> None:
        spec = importlib.util.spec_from_file_location("gen_test_runner", GENERATOR)
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        with tempfile.TemporaryDirectory() as folder:
            generator.TESTS_DIR = folder
            generator.OUT = str(Path(folder) / "GeneratedTestRunner.swift")
            (Path(folder) / "OneTests.swift").write_text("final class OneTests: XCTestCase {\n    func testOne() {}\n}\n")
            with self.assertRaises(SystemExit) as refused:
                generator.main()
            self.assertIn("floor", str(refused.exception))
            self.assertFalse(Path(generator.OUT).exists())


if __name__ == "__main__":
    unittest.main()
