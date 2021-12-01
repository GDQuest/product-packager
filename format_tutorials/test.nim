import std/unittest
import std/parsecsv
import std/strutils
import std/os
import experimental/diff

import format_tutorials

suite "parser":
    # Tests related to the markdown block parser. We should ensure it produces
    # the expected result for different documents.
    test "parse_files":
        echo "tmp"

suite "formatter":
    var parser: CsvParser
    parser.open("test_format_strings.csv")
    parser.readHeaderRow()

    test "format_strings":
        while parser.readRow():
            let
                input = parser.rowEntry("input")
                expected = parser.rowEntry("expected")
                formatted = formatContent(input)
                isExpectedOutput = formatted == expected
            if not input.contains("```"):
                continue
            check(isExpectedOutput)
            if not isExpectedOutput:
                echo "\nDiff between expected and formatted text:\n"
                for item in diffText(expected, formatted):
                    echo "- ", item
                let errorMessage = @[
                    "", "Error: " & parser.rowEntry("error_message"), "",
                    "Input: ", input,
                    "Expected: ", repr(expected),
                    "But instead got: ", repr(formatted)
                ]
                echo errorMessage.join("\n")
