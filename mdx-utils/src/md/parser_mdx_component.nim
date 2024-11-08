# Algorithm:
# 1. Tokenize into smaller tokens
# 2. Find block-level tokens (e.g. code blocks, mdx components) from the tokens
# 3. parse the block tokens in greater detail and find their significant elements
#
# TODO:
# - "Consume" tokens when finding block tokens (set an index that prevents backtracking)
# - Add error handling for invalid syntax
# - Add support for nested components (parse MDX and code inside code fences)
# - test <></> syntax
# - consider case of parsing mdx with line returns within a markdown paragraph. E.g.
# Bla bla <Component>
# ...
# </Component>
# This is not supported by the MDX package.

type
  Range* = object
    start, `end`: int

  TokenType = enum
    Backtick      # `
    OpenBrace     # {
    CloseBrace    # }
    OpenBracket   # [
    CloseBracket  # ]
    OpenAngle     # <
    CloseAngle    # >
    Slash         # /
    Asterisk      # *
    Underscore    # _
    Equals        # =
    Exclamation   # !
    OpenParen     # (
    CloseParen    # )
    DoubleQuote   # "
    SingleQuote   # '
    Comma         # ,
    Semicolon     # ;
    Text          # Any text or whitespace
    Newline       # \n

  BlockType* = enum
      Heading
      Paragraph
      CodeBlock
      # A self-closing component (<Name ... />) is a leaf in the document
      # That's why we differentiate it: it doesn't need to be fed back for
      # recursive parsing.
      SelfClosingMdxComponent
      MdxComponent

  Token = object
    type: TokenType
    range: Range

  BlockToken* = ref object
    type: BlockType
    # Index range for the entire set of tokens corresponding to this block
    # Allows us to retrieve both the tokens and the source text from the first and last token's ranges'
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

  TokenScanner* = ref object
    tokens: seq[Token]
    current: int
    source: string
    peekIndex: int

  Position* = object
    line, column: int

  ParseError* = ref object of Exception
    range: Range
    message: string

proc tokenize(source: string): seq[Token] =
  var tokens: seq[Token] = @[]
  var current = 0

  proc addToken(tokenType: TokenType, start, ende: int) =
    tokens.add(Token(
      type: tokenType,
      range: Range(start: start, `end`: ende)
    ))

  while current < source.len:
    let start = current
    let c = source[current]

    case c
    of '`':
      addToken(Backtick, start, current + 1)
    of '{':
      addToken(OpenBrace, start, current + 1)
    of '}':
      addToken(CloseBrace, start, current + 1)
    of '[':
      addToken(OpenBracket, start, current + 1)
    of ']':
      addToken(CloseBracket, start, current + 1)
    of '<':
      addToken(OpenAngle, start, current + 1)
    of '>':
      addToken(CloseAngle, start, current + 1)
    of '/':
      addToken(Slash, start, current + 1)
    of '*':
      addToken(Asterisk, start, current + 1)
    of '_':
      addToken(Underscore, start, current + 1)
    of '=':
      addToken(Equals, start, current + 1)
    of '!':
      addToken(Exclamation, start, current + 1)
    of '(':
      addToken(OpenParen, start, current + 1)
    of ')':
      addToken(CloseParen, start, current + 1)
    of '"':
      addToken(DoubleQuote, start, current + 1)
    of '\'':
      addToken(SingleQuote, start, current + 1)
    of ',':
      addToken(Comma, start, current + 1)
    of ';':
      addToken(Semicolon, start, current + 1)
    of '\n':
      addToken(Newline, start, current + 1)
    else:
      let textStart = current
      while current < source.len:
        let c = source[current]
        case c
        of '`', '{', '}', '[', ']', '<', '>', '/', '*', '_', '=', '!', '(', ')', '"', '\'', ',', ';', '\n':
          break
        else:
          current += 1
      let textRange = Range(textStart, current)
      if textRange.start != textRange.end:
        tokens.add(Token(
          type: ttText,
          range: Range(start: textRange.start, `end`: textRange.end),
        ))
      continue
    current += 1
  return tokens

proc getString(range: Range, source: string): string {.inline.} =
  return source[range.start..<range.end]

proc getCurrentToken(s: TokenScanner): Token {.inline.} =
  return s.tokens[s.current]

proc advance(s: TokenScanner): Token {.inline.} =
  result = s.getCurrentToken()
  s.current += 1

proc peek(s: TokenScanner, offset: int = 0): Token {.inline.} =
  if s.current + offset >= s.tokens.len:
    return s.tokens[^1] # Return last token
  s.peekIndex = s.current + offset
  return s.tokens[s.peekIndex]

proc matchToken(s: TokenScanner, expected: TokenType): bool {.inline.} =
  if s.getCurrentToken().type != expected:
    return false
  discard s.advance()
  return true

proc isAtEnd((s: TokenScanner): bool {.inline.} =
  return s.current >= s.tokens.len

# BLOCK-LEVEL PARSING
proc blockParseMdxBlock*(s: TokenScanner): BlockToken =
  let start = s.current

  # Get component name
  var name: Range
  let firstToken = s.getCurrentToken()
  if firstToken.type == Text:
    let firstChar = s.source[firstToken.range.start]
    if firstChar >= 'A' and firstChar <= 'Z':
      name = firstToken.range
      discard s.advance()
    else:
      return nil
  else:
    return nil

  # Look for end of opening tag or self-closing mark
  var wasClosingMarkFound = false
  var isSelfClosing = false
  while not s.isAtEnd():
    let token = s.getCurrentToken()
    case token.type:
      of CloseAngle:
        wasClosingMarkFound = true
        discard s.advance()
        break
      of Slash:
        if s.peek().type == CloseAngle:
          isSelfClosing = true
          wasClosingMarkFound = true
          s.current += 2
          break
      else:
        discard s.advance()

  if not wasClosingMarkFound:
    raise new ParseError(
      range: Range(start: start, `end`: s.current),
      message: "Expected closing mark '>' or self-closing mark '/>'"
    )

  let openingTagEnd = s.current
  var bodyEnd = openingTagEnd

  # Find matching closing tag
  if not isSelfClosing:
    let componentName = s.source[name.start..<name.end]
    while not s.isAtEnd():
      if s.getCurrentToken().type == OpenAngle and
          s.peek().type == Slash:
        bodyEnd = s.current
        s.current += 2
        let nameToken = s.getCurrentToken()
        if nameToken.type == Text and
            s.source[nameToken.range.start..<nameToken.range.end] == componentName:
          discard s.advance()
          if s.getCurrentToken().type == CloseAngle:
            discard s.advance()
            break
        break
      discard s.advance()

  if isSelfClosing:
    return BlockToken(
      type: SelfClosingMdxComponent,
      range: Range(start: start, `end`: s.current),
      name: name
    )
  else:
    return BlockToken(
      type: MdxComponent,
      range: Range(start: start, `end`: s.current),
      name: name,
      openingTagRange: Range(start: start, `end`: openingTagEnd),
      bodyRange: Range(start: openingTagEnd, `end`: bodyEnd)
    )

proc blockParseCodeBlock(s: TokenScanner): BlockToken =
  let start = s.current
  # Skip three backticks
  for i in 0..2:
    if not matchToken(s, Backtick):
      return nil

  # Get language
  let languageStart = s.current
  while not s.isAtEnd() and s.getCurrentToken().type != Newline:
    discard s.advance()
  let languageEnd = s.current

  # Skip newline
  if s.getCurrentToken().type == Newline:
    discard s.advance()

  let codeStart = s.current
  var codeEnd = codeStart
  # Find closing backticks
  while not s.isAtEnd():
    if s.getCurrentToken().type == Backtick and
        s.peek(1).type == Backtick and
        s.peek(2).type == Backtick:
      codeEnd = s.current
      s.current += 3
      break
    discard s.advance()

  return BlockToken(
    type: CodeBlock,
    range: Range(start: start, `end`: s.current),
    language: Range(start: languageStart, `end`: languageEnd),
    code: Range(start: codeStart, `end`: codeEnd)
  )

proc parseMdxDocumentBlocks*(s: TokenScanner): seq[BlockToken] =
  var blocks: seq[BlockToken]
  while not s.isAtEnd():
    let token = s.getCurrentToken()
    case token.type:
      of Backtick:
        if s.peek(1).type == Backtick and s.peek(2).type == Backtick:
          let block = blockParseCodeBlock(s)
          if block != nil:
            blocks.add(block)
          else:
            discard s.advance()
        else:
          discard s.advance()
      of OpenAngle:
        discard s.advance()
        let currentBlock = blockParseMdxBlock(s)
        if currentBlock != nil:
          blocks.add(currentBlock)
      else:
        discard s.advance()
  return blocks

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
