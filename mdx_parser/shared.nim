## Shared definitions, data, and utilities for the MDX parser.
type
  Range* = object
    ## A range of character indices in a source string or in a sequence of tokens.
    start*: int
    `end`*: int

  Position* = object
    ## A position in a source document.
    line*, column*: int

  ParseError* = ref object of ValueError
    range*: Range
    message*: string

proc findLineStartIndices*(source: string): seq[int] =
  ## Finds the start indices of each line in the source string.
  ## Run this on a document in case of errors or warnings.
  ## We don't track lines and columns for every token as they're only needed for error reporting.
  result = @[0]
  for i, c in source:
    if c == '\n':
      result.add(i + 1)

proc getLineAndColumn*(lineStartIndices: seq[int], index: int): Position =
  ## Finds the line and column number for the given index
  ## Uses a binary search to limit performance impact
  var min = 0
  var max = lineStartIndices.len - 1

  while min <= max:
    let middle = (min + max).div(2)
    let lineStartIndex = lineStartIndices[middle]

    if index < lineStartIndex:
      max = middle - 1
    elif middle < lineStartIndices.len and index >= lineStartIndices[middle + 1]:
      min = middle + 1
    else:
      return Position(
        line: middle + 1,
        column: index - lineStartIndex + 1
      )
