## Shared definitions, data, and utilities for the MDX parser.
type
  TokenKind =
    concept type T
        T.kind is enum

  Range* = object
    ## A range of character indices in a source string or in a sequence of tokens.
    start*: int
    `end`*: int

  Scanner*[T] = ref object
    tokens*: seq[T]
    current*: int
    source*: string
    peekIndex*: int

  Position* = object ## A position in a source document.
    line*, column*: int

  ParseError* = ref object of ValueError
    range*: Range
    message*: string

proc getString*(range: Range, source: string): string {.inline.} =
  return source[range.start ..< range.end]

proc currentToken*[T: TokenKind](s: Scanner[T]): T {.inline.} =
  s.tokens[s.current]

proc peek*[T: TokenKind](s: Scanner[T], offset: int = 0): T {.inline.} =
  s.peekIndex = s.current + offset
  if s.peekIndex >= s.tokens.len:
    result = s.tokens[^1]
  else:
    result = s.tokens[s.peekIndex]

proc isAtEnd*[T: TokenKind](s: Scanner[T]): bool {.inline.} =
  s.current >= s.tokens.len

proc isPeekSequence*[T: TokenKind](s: Scanner[T], sequence: seq[T]): bool {.inline.} =
  ## Returns `true` if the next tokens in the scanner match the given sequence.
  for i, tokenType in sequence:
    if s.peek(i).kind != tokenType:
      return false
  return true

proc matchToken*[T: TokenKind](s: Scanner, expected: T): bool {.inline.} =
  if s.currentToken.kind != expected:
    return false
  s.current += 1
  return true

proc isAlphanumericOrUnderscore*(c: char): bool {.inline.} =
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit

proc findLineStartIndices*(source: string): seq[int] =
  ## Finds the start indices of each line in the source string.
  ## Run this on a document in case of errors or warnings.
  ## We don't track lines and columns for every token as they're only needed for error reporting.
  result = @[0]
  for i, c in source:
    if c == '\n':
      result.add(i + 1)

proc getLineAndColumn*(lineStartIndices: seq[int], index: int): Position =
  ## Finds the line and column number for the given character index
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
      return Position(line: middle + 1, column: index - lineStartIndex + 1)
