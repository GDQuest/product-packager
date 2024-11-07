# Algorithm:
# 1. Find mdx components as block tokens
# 2. parse the block tokens
#
# TODO:
# - Add error handling for invalid syntax
# - Track line and column numbers for better error messages
# - Add support for nested components
type
  BlockType = enum
    Heading
    Paragraph
    CodeBlock
    # A self-closing component (<Name ... />) is a leaf in the document
    # That's why we differentiate it: it doesn't need to be fed back for
    # recursive parsing.
    SelfClosingMdxComponent
    MdxComponent

  Range = object
    start, `end`: int

  BlockToken = ref object
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
proc parseMdxDocumentBlocks(s: Scanner): seq[BlockToken] =
  # Performs block-level parsing of the document. Returns a sequence of tokens that provide an outline of the document.
  # These block tokens can then be fed to leaf parsing functions for further processing.
  var tokens: seq[Token]
  while not s.isAtEnd():
    let token = parseBlockToken(s)
    tokens.add(token)
  return tokens

proc parseBlockToken(s: Scanner): BlockToken =
  # Parses and returns one block-level token.
  # TODO: block-level tokens start from a newline?
  let start = s.current
  while not s.isAtEnd():
    let c = s.getCurrentChar()
    case c
    of '`':
      if s.peekString("```"):
        return parseCodeBlock(s)

    # Potential start of an mdx component
    of '<':
      # TODO: test <></> syntax
      # TODO: use s's peek offset prop?
      # TODO: consider case of parsing mdx with line returns within a markdown paragraph. E.g.
      # Bla bla <Component>
      #
      # ...
      #
      # </Component>
      # This is not supported by the MDX package.
      let start = s.current
      var offset = 1
      while s.peekAt(offset) == ' ':
        offset += 1

      # Get component name
      var name: Range
      name.start = s.current + offset
      while isAlphanumericOrUnderscore(s.peekAt(offset)):
        offset += 1
      name.end = s.current + offset

      # Look for end of opening tag or self-closing mark
      var isSelfClosing = false
      while not s.isAtEnd():
        case s.peekAt(offset):
          of '>':
            offset += 1
            break
          of '/':
            if s.peekAt(offset + 1) == '>':
              isSelfClosing = true
              offset += 2
              break
          else:
            offset += 1

      let openingTagEnd = s.current + offset
      var bodyEnd = openingTagEnd
      # Find matching closing tag
      if not isSelfClosing:
        let componentName = s.source[nameStart..<nameEnd]
        while not s.isAtEnd():
          if s.peekString("</"):
            bodyEnd = s.current
            # TODO: use s.peekIndex throughout code, removing need for this and offset var
            offset += 2
            while s.peekAt(offset) == ' ':
              offset += 1
            if s.peekString(componentName):
              offset += componentName.len
              if s.peekAt(offset) == '>':
                offset += 1
                break
            offset = s.peekIndex - s.current
            break
          offset += 1

      s.current += offset
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

    else:
      discard s.advance()

proc parseCodeBlock(s: Scanner): Token =
  # The parsing starts at the first of the top three backticks
  let start = s.current
  s.advanceToPeek()
  # Look for language, an alphanumeric sequence
  var bodyEnd = -1
  while not s.isAtEnd():
    if s.matchString("```"):
      bodyEnd = s.current - 3
      break
    discard s.advance()

  let end = s.current
  let languageStart = start + 3
  let languageEnd = s.current - 3
  return Token(
    tokenType: CodeBlock,
    range: Range(start: start, `end`: end),
    language: Range(start: languageStart, `end`: languageEnd)
  )
