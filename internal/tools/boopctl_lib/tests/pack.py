"""What the tools' tests need of the chosen character pack (characters/CHARACTER.md)."""
import unittest

from boopctl_lib.common import PACK

# The tests that read the pack's recorded takes skip for a pack with no voice (§8).
needs_voice = unittest.skipUnless(PACK.exists(), "needs a character pack with a voice")
