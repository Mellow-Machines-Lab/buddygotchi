import unittest

from textkit.wordcount import count


class WordCountTests(unittest.TestCase):
    def test_counts(self):
        self.assertEqual(count("the cat. The dog!")["the"], 2)


if __name__ == "__main__":
    unittest.main()
