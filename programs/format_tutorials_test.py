"""Tests for format_tutorials.py. The `test_expected_output()` function loads a
table of strings and ensures that each leads to the expected output when run
through `process_content()`"""
from format_tutorials import *
import csv
import os

def test_expected_output():
    input_strings: list = None

    csv_file_path: str = os.path.join(os.path.dirname(__file__), "tests/format_tutorial_test_strings.csv")
    with open(csv_file_path, "r") as csv_file:
        reader = csv.DictReader(csv_file)
        input_strings = [row for row in reader]

    for row in input_strings:
        input_line: str = row["input"]
        expected_output: str = row["expected_output"]
        error_message: str = row["error_message"]
        assert process_content(input_line) == expected_output, error_message

if __name__ == '__main__':
    test_expected_output()
