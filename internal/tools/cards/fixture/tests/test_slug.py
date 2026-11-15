import unittest

from textkit.slug import slugify


class SlugTests(unittest.TestCase):
    def test_simple(self):
        self.assertEqual(slugify("Hello World"), "hello-world")

    def test_double_spaces(self):
        self.assertEqual(slugify("Hello   big  World"), "hello-big-world")

    def test_punctuation(self):
        self.assertEqual(slugify("What's new, 2026?"), "what-s-new-2026")


if __name__ == "__main__":
    unittest.main()
