import copy
import unittest
from run import validate


class ResultContract(unittest.TestCase):
    def setUp(self):
        self.result = dict(reason='graduated', exit_code=0, pointer_fallbacks=0,
                           field_click_failures=[], movement_failures=[], movement_records=[dict(passed=True)])

    def test_classified_caps_are_unfinished_observations(self):
        for code, reason in [(0, 'graduated'), (4, 'round cap 60 at 3-1'), (6, 'attempt cap 10 at 3-1')]:
            result = dict(self.result, exit_code=code, reason=reason)
            validate(result, code)

    def test_input_and_movement_errors_are_rejected(self):
        for field, value in [('pointer_fallbacks', 1), ('field_click_failures', ['missed']),
                             ('movement_failures', ['cost']), ('movement_records', []),
                             ('movement_records', [dict(passed=False)]), ('exit_code', 4)]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate(dict(copy.deepcopy(self.result), **{field: value}), 0)
        with self.assertRaises(ValueError):
            validate(dict(self.result, exit_code=7, reason='movement postcondition failure'), 7)


if __name__ == '__main__':
    unittest.main()
