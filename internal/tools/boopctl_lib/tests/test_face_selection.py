"""VERIFICATION.md L1/L2: never compare a gel picture to a pixel golden."""
import os
import unittest
from unittest.mock import patch
from boopctl_lib import cli, scenario

class FaceSelectionTests(unittest.TestCase):
    def test_without_a_face_the_pack_in_use_says(self):
        for pack, face in (('pixel', 'pixel'), ('boop', 'gel')):
            with patch.dict(os.environ, {'BOOP_SIM_FACE': '', 'CHARACTER': pack}):
                self.assertEqual(scenario.face(), face)

    def test_unknown_keeps_pixel_compatibility(self):
        for value in ('unknown', 'pixel'):
            with patch.dict(os.environ, {'BOOP_SIM_FACE': value}):
                self.assertEqual(scenario.face(), 'pixel')
                self.assertEqual(scenario.golden_dir(), scenario.GOLDEN)
                self.assertTrue(all(path.parent==scenario.SCENARIOS for path in scenario.all_scenarios()))

    def test_gel_has_separate_scenarios_and_goldens(self):
        with patch.dict(os.environ, {'BOOP_SIM_FACE': 'gel'}):
            self.assertEqual(scenario.golden_dir().name, 'golden-gel')
            self.assertEqual({path.stem for path in scenario.all_scenarios()}, {'comedy','done','drawer','finish','gestures','hush','lane','layers','moods','notice','occasions','pastimes','replies','sign','states','stream','swipes'})
            self.assertEqual(scenario.resolve('states').parent, scenario.GEL_SCENARIOS)
        self.assertEqual(cli.build_parser().parse_args(['sim','--face','gel']).face,'gel')
