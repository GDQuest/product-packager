import std/unittest
import std/parsecsv
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
            let
                input = parser.rowEntry("input")
                expected = parser.rowEntry("expected")
                isExpectedOutput = formatContent(input) == expected
            check(isExpectedOutput)
            if not isExpectedOutput: echo(parser.rowEntry("error_message"))
