import std/unittest
import std/parsecsv
import std/strutils
import format

suite "parser":
    # Tests related to the markdown block parser. We should ensure it produces
    # the expected result for different documents.
    test "parse_files":
        echo "tmp"

suite "formatter":
    var parser: CsvParser
    parser.open("data/test_format_strings.csv")
    parser.readHeaderRow()

    test "format_strings":
        while parser.readRow():
            let
                input = parser.rowEntry("input")
                expected = parser.rowEntry("expected")
                error = parser.rowEntry("error_message")
            # if not error.startsWith("Directory paths should be in inline code"): continue
            let
                formatted = formatContent(input)
                isExpectedOutput = formatted == expected
            check(isExpectedOutput)
            if not isExpectedOutput:
                let errorMessage = @[
                    "", "Error: " & error, "",
                    "Input: ", input,
                    "Expected: ", expected,
                    "But instead got: ", formatted
                ]
                echo errorMessage.join("\n")
