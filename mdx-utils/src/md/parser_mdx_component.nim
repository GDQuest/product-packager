# Algorithm:
# 1. Find mdx components as block tokens
# 2. parse the block tokens
#
# TODO:
# - Add error handling for invalid syntax
# - Add support for nested components (parse MDX and code inside code fences)
# - test <></> syntax
# - consider case of parsing mdx with line returns within a markdown paragraph. E.g.
# Bla bla <Component>
# ...
# </Component>
# This is not supported by the MDX package.
type
  BlockType* = enum
    Heading
    Paragraph
    CodeBlock
    # A self-closing component (<Name ... />) is a leaf in the document
    # That's why we differentiate it: it doesn't need to be fed back for
    # recursive parsing.
    SelfClosingMdxComponent
    MdxComponent

  Range* = object
    start, `end`: int

  BlockToken* = ref object
    type: BlockType
    # Index range for the entire string corresponding to the token
    range: Range
    case type
      of CodeBlock:
        language: Range
        code: Range
      of SelfClosingMdxComponent:
        name: Range
      of MdxComponent:
        name: Range
        # This allows us to distinguish the opening tag and body for further parsing
        openingTagRange: Range
        bodyRange: Range

  Scanner* = ref object
    source: string
    current: int
    indentLevel: int
    bracketDepth: int
    peekIndex: int

  Position* = object
    line, column: int

  ParseError* = ref object of Exception
    range: Range
    message: string

proc getString(range: Range, source: string): string {.inline.} =
  return source[range.start..<range.end]

proc getCurrentChar(s: Scanner): char {.inline.} =
  ## Returns the current character without advancing the scanner's current index
  return s.source[s.current]

proc advance(s: Scanner): char {.inline.} =
  ## Reads and returns the current character, then advances the scanner by one
  result = s.source[s.current]
  s.current += 1

proc peekAt(s: Scanner, offset: int): char {.inline.} =
  ## Peeks at a specific offset and returns the character without advancing the scanner
  s.peekIndex = s.current + offset
  if s.peekIndex >= s.source.len:
    return '\0'
  return s.source[s.peekIndex]

proc peekString(s: Scanner, expected: string): bool {.inline.} =
  ## Peeks ahead to check if the expected string is present without advancing
  ## Returns true if the string is found, false otherwise
  let length = expected.len
  for i in 0..<length:
    if peekAt(s, i) != expected[i]:
      return false
  s.peekIndex = s.current + length
  return true

proc advanceToPeek(s: Scanner) {.inline.} =
  ## Advances the scanner to the stored getCurrentChar index
  s.current = s.peekIndex

proc match(s: Scanner, expected: char): bool {.inline.} =
  ## Returns true and advances the scanner if and only if the current character matches the expected character
  ## Otherwise, returns false
  if s.getCurrentChar() != expected:
    return false
  discard s.advance()
  return true

proc matchString(s: Scanner, expected: string): bool {.inline.} =
  ## Returns true and advances the scanner if and only if the next characters match the expected string
  if s.peekString(expected):
    s.advanceToPeek()
    return true
  return false

proc skipWhitespace(s: Scanner) {.inline.} =
  ## Peeks at the next characters and advances the scanner until a non-whitespace character is found
  while true:
    let c = s.getCurrentChar()
    case c:
    of ' ', '\r', '\t':
      discard s.advance()
    else:
      break

proc isAtEnd(s: Scanner): bool {.inline.} =
  s.current >= s.source.len

proc isAlphanumericOrUnderscore(c: char): bool {.inline.} =
  ## Returns true if the character is a letter, digit, or underscore
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit

proc isAlphaOrDash(c: char): bool {.inline.} =
  ## Returns true if the character is a letter, digit, or underscore
  return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '-' or c == '_'

proc scanIdentifier(s: Scanner): tuple[start: int, `end`: int] {.inline.} =
  let start = s.current
  while isAlphanumericOrUnderscore(s.getCurrentChar()):
    discard s.advance()
  result = (start, s.current)

proc scanToEndOfLine(s: Scanner): tuple[start, `end`: int] {.inline.} =
  let start = s.current
  let length = s.source.len
  var offset = 0
  var c = s.source[s.current]
  while c != '\n':
    offset += 1
    if s.current + offset >= length:
      break
    c = s.source[s.current + offset]
  s.current += offset
  if s.current < length:
    discard s.advance()
  result = (start, s.current)

# BLOCK-LEVEL PARSING
proc blockParseMdxBlock*(s: Scanner): BlockToken =
  # TODO: this is currently assumes that the block is formed properly, but this needs to handle errors
  # TODO: What about a case like "The < sign is bla bla bla"? This will be parsed as a potential MdxComponent and might trigger an error. We need to handle this case.
  let start = s.current
  while s.peekAt(1) == ' ':
    s.peekIndex += 1

  # Get component name
  var name: Range
  name.start = s.peekIndex
  let firstChar = s.peekAt(s.peekIndex - s.current)
  if (firstChar >= 'A' and firstChar <= 'Z'):
    while isAlphanumericOrUnderscore(s.peekAt(s.peekIndex - s.current)):
      s.peekIndex += 1
    name.end = s.peekIndex
  else:
    return nil

  # Look for end of opening tag or self-closing mark
  var wasClosingMarkFound = false
  var isSelfClosing = false
  while not s.isAtEnd():
    case s.peekAt(s.peekIndex - s.current):
      of '>':
        s.peekIndex += 1
        wasClosingMarkFound = true
        break
      of '/':
        if s.peekAt(s.peekIndex - s.current + 1) == '>':
          isSelfClosing = true
          s.peekIndex += 2
          wasClosingMarkFound = true
          break
      else:
        s.peekIndex += 1

  if not wasClosingMarkFound:
    raise new ParseError(
      range: Range(start, s.peekIndex),
      message: "Expected closing mark '>' or self-closing mark '/>'"
    )
  let openingTagEnd = s.peekIndex
  var bodyEnd = openingTagEnd
  # Find matching closing tag
  if not isSelfClosing:
    let componentName = s.source[name.start..<name.end]
    while not s.isAtEnd():
      if s.peekString("</"):
        bodyEnd = s.current
        while s.peekAt(s.peekIndex - s.current) == ' ':
          s.peekIndex += 1
        if s.peekString(componentName):
          s.peekIndex += componentName.len
          if s.peekAt(s.peekIndex - s.current) == '>':
            s.peekIndex += 1
            break
        break
      s.peekIndex += 1

  s.current = s.peekIndex
  if isSelfClosing:
    return BlockToken(
      kind: SelfClosingMdxComponent,
      start: start, end: s.current,
      name: name,
    )
  else:
    return BlockToken(
      kind: MdxComponent,
      start: start, end: s.current,
      name: name,
      openingTagRange: Range(start: start, `end`: openingTagEnd),
      bodyRange: Range(start: openingTagEnd + 1, `end`: bodyEnd),
    )

proc blockParseCodeBlock(s: Scanner): BlockToken =
  # The parsing starts at the first of the top three backticks
  let start = s.current
  # Jump after the first three backticks
  s.advanceToPeek()

  # Assume the language follows the first three backticks
  let languageRange = scanToEndOfLine(s)

  var bodyEnd = -1
  while not s.isAtEnd():
    if s.matchString("```"):
      bodyEnd = s.current - 3
      break
    s.current += 1

  let end = s.current
  return BlockToken(
    tokenType: CodeBlock,
    range: Range(start: start, `end`: end),
    language: languageRange,
    code: Range(start: languageRange.end + 1, `end`: bodyEnd),
  )

proc parseMdxDocumentBlocks* (s: Scanner): seq[BlockToken] =
  # Performs block-level parsing of the document. Returns a sequence of block tokens that provide an outline of the document.
  # These block tokens can then be fed to leaf parsing functions for further processing.
  var tokens: seq[BlockToken]
  while not s.isAtEnd():
    let c = s.getCurrentChar()
    case c
    of '`':
      if s.peekString("```"):
        tokens.add(parseCodeBlock(s))
      else:
        s.current += 1
    of '<':
      # A < may indicate the start of an MdxComponent, but it can also be part of regular text
      let token = blockParseMdxBlock(s)
      if token != nil:
        tokens.add(token)
      else:
        s.current += 1
        continue
    else:
      s.current += 1
  return tokens

# Utilities to get line and column numbers
# Use these when you need to report errors or warnings
# If there are no errors, we don't need to get line numbers
proc findLineStartIndices(source: string): seq[int] =
  result = @[0]
  for i, c in source:
    if c == '\n':
      result.add(i + 1)

proc getLineAndColumn(lineStartIndices: seq[int], index: int): Position =
  # Finds the line and column number for the given index
  # Uses a binary search to limit performance impact
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
