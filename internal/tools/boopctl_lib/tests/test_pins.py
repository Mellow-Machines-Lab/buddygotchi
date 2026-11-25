"""VERIFICATION.md L1: which shots `sim` compares with a golden. The gel's
set is frozen small while its pictures are redesigned: one or two pinned
shots a scenario, about 70 in all, and a golden for each and no other."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from boopctl_lib import scenario


class PinTests(unittest.TestCase):
    def test_each_gel_scenario_pins_one_or_two_shots_each_with_a_golden(self):
        with patch.dict(os.environ, {'BOOP_SIM_FACE': 'gel'}):
            total = 0
            for path in scenario.all_scenarios():
                with self.subTest(path.stem):
                    pins = scenario.pinned_shots(path)
                    self.assertIn(len(pins), (1, 2))
                    goldens = {png.stem for png in (scenario.golden_dir() / path.stem).glob('*.png')}
                    self.assertEqual(goldens, pins)
                    total += len(pins)
            self.assertLessEqual(total, 70)

    def test_pin_marks_the_gel_s_shots_and_pixel_pins_every_one(self):
        steps = [{'clock': 0}, {'shot': 'kept', 'pin': True}, {'shot': 'taken'}, {'shot': 'off', 'pin': False}]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'some.jsonl'
            path.write_text('// a comment\n\n' + '\n'.join(json.dumps(step) for step in steps) + '\n')
            with patch.dict(os.environ, {'BOOP_SIM_FACE': 'gel'}):
                self.assertEqual(scenario.pinned_shots(path), {'kept'})
            with patch.dict(os.environ, {'BOOP_SIM_FACE': 'pixel'}):
                self.assertEqual(scenario.pinned_shots(path), {'kept', 'taken'})


if __name__ == '__main__':
    unittest.main()
