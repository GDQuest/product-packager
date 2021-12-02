import std/unittest
import std/parsecsv
import std/strutils
import std/os

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
            let input = parser.rowEntry("input")
            # if not input.startsWith("Drag"):
                # continue
            let
                expected = parser.rowEntry("expected")
                formatted = formatContent(input)
                isExpectedOutput = formatted == expected
            check(isExpectedOutput)
            if not isExpectedOutput:
                let errorMessage = @[
                    "", "Error: " & parser.rowEntry("error_message"), "",
                    "Input: ", input,
                    "Expected: ", repr(expected),
                    "But instead got: ", repr(formatted)
                ]
                echo errorMessage.join("\n")
