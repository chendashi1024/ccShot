import unittest
from metrics import measure


class MetricsTests(unittest.TestCase):
    def test_substitution_insertion_deletion(self):
        self.assertEqual(measure('你好世界', '你好世间')['edits'], 1)
        self.assertEqual(measure('你好', '你很好')['insertions'], 1)
        self.assertEqual(measure('你好世界', '你世界')['deletions'], 1)
        self.assertAlmostEqual(measure('你好世界', '你好世间')['cer'], 0.25)

    def test_whitespace_only_normalization_keeps_punctuation(self):
        self.assertEqual(measure('你好\n世界！', '你好 世界！')['edits'], 0)
        self.assertEqual(measure('你好！', '你好!')['substitutions'], 1)
        self.assertEqual(measure('API 128.50', 'API128.50')['edits'], 0)

    def test_empty_and_exact(self):
        self.assertEqual(measure('', '')['edits'], 0)
        self.assertEqual(measure('本地识别', '本地识别')['exact'], True)
        self.assertEqual(measure('甲乙丙', '')['deletions'], 3)


if __name__ == '__main__':
    unittest.main()
