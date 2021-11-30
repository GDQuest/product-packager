import std/unittest
import std/parsecsv
import std/strutils

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
            check(isExpectedOutput)
            if not isExpectedOutput:
                let errorMessage = @[
                    "\n",
                    "Error: ", parser.rowEntry("error_message"),
                    "\n",
                    "Input: ", input,
                    "Expected: ", expected,
                    "But instead got: ", formatted, "\n",
                ]
                echo errorMessage.join("\n")
