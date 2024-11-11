# Minimal MDX parser for the needs of the GDQuest platform.
#
# This parser is a work in progress.
#
# It is not meant to become a full commonmark-compliant parser: many markdown
# features are replaced well with react or web components.
# Instead, this parser aims to run fast and be easy to maintain.
#
# Algorithm:
# 1. Tokenize into smaller tokens
# 2. Find block-level tokens (e.g. code blocks, mdx components) from the tokens
# 3. parse the block tokens in greater detail and find their significant elements
#
# TODO:
# - "Consume" tokens when finding block tokens (set an index that prevents backtracking)
# - Add error handling for invalid syntax
# - Add support for nested components (parse MDX and code inside code fences etc.)
# - test <></> syntax
# - consider case of parsing mdx with line returns within a markdown paragraph. E.g.
# Bla bla <Component>
# ...
# </Component>
# This is not supported by the MDX package.
type
  Range* = object
    start*, `end`*: int

  TokenType* = enum
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
    EOF           # End of file marker

  BlockType* = enum
    Heading
    Paragraph
    CodeBlock
    MdxComponent

  Token* = object
    kind*: TokenType
    range*: Range

  BlockToken* = ref object
    # Index range for the entire set of tokens corresponding to this block
    # Allows us to retrieve both the tokens and the source text from the first and last token's ranges'
    range*: Range
    case kind*: BlockType
      of CodeBlock:
        language*: Range
        code*: Range
      of MdxComponent:
        name*: Range
        isSelfClosing*: bool
        # This allows us to distinguish the opening tag and body for further parsing
        openingTagRange*: Range
        bodyRange*: Range
      of Heading, Paragraph:
        discard

  TokenScanner* = ref object
    tokens*: seq[Token]
    current*: int
    source*: string
    peekIndex*: int

  Position* = object
    line*, column*: int

  ParseError* = ref object of ValueError
    range*: Range
    message*: string

proc tokenize*(source: string): seq[Token] =
  var tokens: seq[Token] = @[]
  var current = 0

  proc addToken(tokenType: TokenType, start, ende: int) =
    tokens.add(Token(
      kind: tokenType,
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
    of '\0':
      addToken(EOF, start, current + 1)
    else:
      let textStart = current
      while current < source.len:
        let c = source[current]
        case c
        of '`', '{', '}', '[', ']', '<', '>', '/', '*', '_', '=', '!', '(', ')', '"', '\'', ',', ';', '\n':
          break
        else:
          current += 1
      let textRange = Range(start: textStart, `end`: current)
      if textRange.start != textRange.end:
        tokens.add(Token(
          kind: Text,
          range: Range(start: textRange.start, `end`: textRange.end),
        ))
      continue
    current += 1
  return tokens

proc getString*(range: Range, source: string): string {.inline.} =
  return source[range.start..<range.end]

proc getCurrentToken(s: TokenScanner): Token {.inline.} =
  return s.tokens[s.current]

proc advance(s: TokenScanner): Token {.inline.} =
  result = s.getCurrentToken()
  s.current += 1

proc peek(s: TokenScanner, offset: int = 0): Token {.inline.} =
  s.peekIndex = s.current + offset
  if s.peekIndex >= s.tokens.len:
    return s.tokens[^1]
  return s.tokens[s.peekIndex]

proc matchToken(s: TokenScanner, expected: TokenType): bool {.inline.} =
  if s.getCurrentToken().kind != expected:
    return false
  s.current += 1
  return true

proc isAtEnd(s: TokenScanner): bool {.inline.} =
  return s.current >= s.tokens.len

proc isAlphanumericOrUnderscore(c: char): bool {.inline.} =
  ## Returns true if the character is a letter, digit, or underscore
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit

# BLOCK-LEVEL PARSING
proc blockParseMdxBlock*(s: TokenScanner): BlockToken =
  let start = s.current

  # Get component name. It has to start with an uppercase letter.
  var name: Range
  let firstToken = s.getCurrentToken()
  if firstToken.kind == Text:
    let firstChar = s.source[firstToken.range.start]
    if firstChar >= 'A' and firstChar <= 'Z':
      # Find end of component name (first non-alphanumeric/underscore character)
      var nameEnd = firstToken.range.start + 1
      while nameEnd < firstToken.range.end:
        let c = s.source[nameEnd]
        if not isAlphanumericOrUnderscore(c):
          break
        nameEnd += 1
      name = Range(start: firstToken.range.start, `end`: nameEnd)
      s.current += 1
    else:
      return nil
  else:
    return nil

  # Look for end of opening tag or self-closing mark
  var wasClosingMarkFound = false
  var isSelfClosing = false
  while not s.isAtEnd():
    let token = s.getCurrentToken()
    case token.kind:
      of Slash:
        let nextToken = s.peek(1)
        if nextToken.kind == CloseAngle:
          isSelfClosing = true
          wasClosingMarkFound = true
          s.current += 2
          break
        else:
          s.current += 1
      of CloseAngle:
        wasClosingMarkFound = true
        s.current += 1
        break
      else:
        s.current += 1

  if not wasClosingMarkFound:
    raise ParseError(
      range: Range(start: start, `end`: s.current),
      message: "Expected closing mark '>' or self-closing mark '/>'"
    )

  let openingTagEnd = s.current
  var bodyEnd = openingTagEnd

  # Find matching closing tag
  if not isSelfClosing:
    let componentName = s.source[name.start..<name.end]
    while not s.isAtEnd():
      if s.getCurrentToken().kind == OpenAngle and
          s.peek().kind == Slash:
        bodyEnd = s.current
        s.current += 2
        let nameToken = s.getCurrentToken()
        if nameToken.kind == Text and
            s.source[nameToken.range.start..<nameToken.range.end] == componentName:
          s.current += 1
          if s.getCurrentToken().kind == CloseAngle:
            s.current += 1
            break
        break
      s.current += 1

  if isSelfClosing:
    return BlockToken(
      kind: MdxComponent,
      isSelfClosing: true,
      range: Range(start: start, `end`: s.current),
      name: name
    )
  else:
    return BlockToken(
      kind: MdxComponent,
      isSelfClosing: false,
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
  var languageRange = Range(start: 0, `end`: 0)
  if s.getCurrentToken().kind == Text:
    languageRange = s.getCurrentToken().range
  s.current += 1

  # Skip newline
  if s.getCurrentToken().kind == Newline:
    s.current += 1

  let codeStart = s.current
  var codeEnd = codeStart
  # Find closing backticks
  while not s.isAtEnd():
    if s.getCurrentToken().kind == Backtick and
        s.peek(1).kind == Backtick and
        s.peek(2).kind == Backtick:
      codeEnd = s.current
      s.current += 3
      break
    s.current += 1

  return BlockToken(
    kind: CodeBlock,
    range: Range(start: start, `end`: s.current),
    language: languageRange,
    code: Range(start: codeStart, `end`: codeEnd)
  )

proc parseMdxDocumentBlocks*(s: TokenScanner): seq[BlockToken] =
  var blocks: seq[BlockToken]
  while not s.isAtEnd():
    let token = s.getCurrentToken()
    case token.kind:
      of Backtick:
        if s.peek(1).kind == Backtick and s.peek(2).kind == Backtick:
          let codeBlock = blockParseCodeBlock(s)
          if codeBlock != nil:
            blocks.add(codeBlock)
          else:
            s.current += 1
        else:
          s.current += 1
      of OpenAngle:
        s.current += 1
        let mdxBlock = blockParseMdxBlock(s)
        if mdxBlock != nil:
          blocks.add(mdxBlock)
        else:
          s.current += 1
      else:
        s.current += 1
  result = blocks

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

proc echoBlockToken*(token: BlockToken, source: string, indent: int = 0) =
  echo "Block: ", $token.kind
  echo "Range:"
  echo "  Start: ", token.range.start
  echo "  End: ", token.range.end

  case token.kind:
    of CodeBlock:
      echo "Language: ", getString(token.language, source)
      echo "Code: ", getString(token.code, source)
    of MdxComponent:
      echo "Name: ", getString(token.name, source)
      echo "Self closing: ", token.isSelfClosing
      if not token.isSelfClosing:
        echo "Opening tag range: ", token.openingTagRange.start, "..", token.openingTagRange.end
        echo "Body range: ", token.bodyRange.start, "..", token.bodyRange.end
    else:
      discard

proc echoBlockTokens*(tokens: seq[BlockToken], source: string) =
  echo "Parsed Block Tokens:"
  for token in tokens:
    echoBlockToken(token, source)
    echo ""
