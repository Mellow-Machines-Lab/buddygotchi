"""VERIFICATION.md L1: which shots `sim` compares with a golden. The gel's
set is frozen small while its pictures are redesigned: one or two pinned
shots a scenario, about 60 in all, and a golden for each and no other."""
import json
import tempfile
import unittest
from pathlib import Path
from boopctl_lib import scenario


class PinTests(unittest.TestCase):
    def test_the_scenarios_are_boop_s_pack_s(self):
        self.assertEqual(scenario.GOLDEN.name, 'golden-gel')
        self.assertEqual(scenario.resolve('states').parent, scenario.SCENARIOS)
        self.assertTrue(all(path.parent == scenario.SCENARIOS for path in scenario.all_scenarios()))

    def test_each_gel_scenario_pins_one_or_two_shots_each_with_a_golden(self):
        total = 0
        for path in scenario.all_scenarios():
            with self.subTest(path.stem):
                pins = scenario.pinned_shots(path)
                self.assertIn(len(pins), (1, 2))
                goldens = {png.stem for png in (scenario.GOLDEN / path.stem).glob('*.png')}
                self.assertEqual(goldens, pins)
                total += len(pins)
        self.assertLessEqual(total, 70)

    def test_pin_marks_the_shots_compared(self):
        steps = [{'clock': 0}, {'shot': 'kept', 'pin': True}, {'shot': 'taken'}, {'shot': 'off', 'pin': False}]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'some.jsonl'
            path.write_text('// a comment\n\n' + '\n'.join(json.dumps(step) for step in steps) + '\n')
            self.assertEqual(scenario.pinned_shots(path), {'kept'})


if __name__ == '__main__':
    unittest.main()
