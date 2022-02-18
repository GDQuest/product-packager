import std/
  [ os
  , parsecsv
  , strutils
  , unittest
  ]
import format

suite "Formatter":
  var parser: CsvParser
  parser.open(currentSourcePath.parentDir / "data" / "testformat.csv")
  parser.readHeaderRow()

  test "formatContent":
    while parser.readRow():
      let
        input = parser.rowEntry("input")
        expected = parser.rowEntry("expected")
        formatted = formatContent(input).strip(leading = false)
        isExpectedOutput = formatted == expected

      check(isExpectedOutput)
      if not isExpectedOutput:
        stderr.writeLine ["", "Input: ", input, "Expected: ", expected, "But instead got: ", formatted].join("\n")