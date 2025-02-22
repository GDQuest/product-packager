import strutils, sequtils, tables

type
  MDXTokenType = enum
    Text
    CodeBlockStart
    CodeBlockEnd
    InlineCode
    BoldStart
    BoldEnd
    ItalicStart
    ItalicEnd
    LinkStart
    LinkEnd
    LinkTextStart
    LinkTextEnd
    LinkURLStart
    LinkURLEnd
    HeadingStart
    HeadingEnd
    Newline
    EOF

type
  MDXToken = object
    tokenType: MDXTokenType
    value: string
    line: int
    col: int

type
  MDXLexer = object
    input: string
    pos: int
    line: int
    col: int
    tokens: seq[MDXToken]

proc newMDXLexer(input: string): MDXLexer =
  MDXLexer(input: input, pos: 0, line: 1, col: 1, tokens: @[])

proc advance(lexer: var MDXLexer, n: int = 1) =
  for i in 1 ..< n:
    if lexer.pos < len(lexer.input):
      if lexer.input[lexer.pos] == '\n':
        lexer.line += 1
        lexer.col = 1
      else:
        lexer.col += 1
      lexer.pos += 1

proc peek(lexer: MDXLexer, n: int = 0): char =
  if lexer.pos + n < len(lexer.input):
    lexer.input[lexer.pos + n]
  else:
    '\0' # Null character for EOF

proc matchChar(lexer: var MDXLexer, charToMatch: char): bool =
  if peek(lexer) == charToMatch:
    advance(lexer)
    return true
  else:
    return false

proc matchString(lexer: var MDXLexer, stringToMatch: string): bool =
  if lexer.pos + len(stringToMatch) <= len(lexer.input) and
     lexer.input[lexer.pos ..< lexer.pos + len(stringToMatch)] == stringToMatch:
    advance(lexer, len(stringToMatch))
    return true
  else:
    return false

proc skipWhitespace(lexer: var MDXLexer) =
  while peek(lexer).isSpace:
    advance(lexer)

proc lexText(lexer: var MDXLexer): MDXToken =
  var value = ""
  while peek(lexer) != '\0' and not peek(lexer) in ['`', '*', '[', ']', '<', '\n', '#']: # Add other special characters
    value.add(peek(lexer))
    advance(lexer)

  MDXToken(tokenType: MDXTokenType.Text, value: value.strip(), line: lexer.line, col: lexer.col - len(value))

proc lexCodeBlock(lexer: var MDXLexer): MDXToken =
    if matchString(lexer, "```"):
        return MDXToken(tokenType: MDXTokenType.CodeBlockStart, value: "```", line: lexer.line, col: lexer.col - 3)
    elif matchString(lexer, "```"):
        return MDXToken(tokenType: MDXTokenType.CodeBlockEnd, value: "```", line: lexer.line, col: lexer.col - 3)
    else:
        return MDXToken(tokenType: MDXTokenType.Text, value: "", line: lexer.line, col: lexer.col) # Handle error or other content


proc lexInlineCode(lexer: var MDXLexer): MDXToken =
  if matchChar(lexer, '`'):
      return MDXToken(tokenType: MDXTokenType.InlineCode, value: "`", line: lexer.line, col: lexer.col -1)
  else:
      return MDXToken(tokenType: MDXTokenType.Text, value: "", line: lexer.line, col: lexer.col)


proc lexBold(lexer: var MDXLexer): MDXToken =
    if matchString(lexer, "**"):
        return MDXToken(tokenType: MDXTokenType.BoldStart, value: "**", line: lexer.line, col: lexer.col - 2)
    elif matchString(lexer, "**"):
        return MDXToken(tokenType: MDXTokenType.BoldEnd, value: "**", line: lexer.line, col: lexer.col - 2)
    else:
        return MDXToken(tokenType: MDXTokenType.Text, value: "", line: lexer.line, col: lexer.col)

proc lexItalic(lexer: var MDXLexer): MDXToken =
    if matchChar(lexer, "*"):
        return MDXToken(tokenType: MDXTokenType.ItalicStart, value: "*", line: lexer.line, col: lexer.col - 1)
    elif matchChar(lexer, "*"):
        return MDXToken(tokenType: MDXTokenType.ItalicEnd, value: "*", line: lexer.line, col: lexer.col - 1)
    else:
        return MDXToken(tokenType: MDXTokenType.Text, value: "", line: lexer.line, col: lexer.col)


proc lexLink(lexer: var MDXLexer): seq[MDXToken] =
  var tokens: seq[MDXToken] = @[]
  if matchChar(lexer, '['):
    tokens.add(MDXToken(tokenType: MDXTokenType.LinkStart, value: "[", line: lexer.line, col: lexer.col - 1))
    var textTokens = tokenizeUntil(lexer, ']') # Tokenize the link text
    tokens.add(textTokens)

    if matchChar(lexer, ']'):
      tokens.add(MDXToken(tokenType: MDXTokenType.LinkTextEnd, value: "]", line: lexer.line, col: lexer.col -1))
      if matchChar(lexer, '('):
        tokens.add(MDXToken(tokenType: MDXTokenType.LinkURLStart, value: "(", line: lexer.line, col: lexer.col - 1))
        var urlTokens = tokenizeUntil(lexer, ')') # Tokenize the link URL
        tokens.add(urlTokens)
        if matchChar(lexer, ')'):
            tokens.add(MDXToken(tokenType: MDXTokenType.LinkURLEnd, value: ")", line: lexer.line, col: lexer.col -1))
            tokens.add(MDXToken(tokenType: MDXTokenType.LinkEnd, value: "", line: lexer.line, col: lexer.col))
        else:
            tokens.add(MDXToken(tokenType: MDXTokenType.Text, value: "", line: lexer.line, col: lexer.col)) # Handle missing ')'
      else:
          tokens.add(MDXToken(tokenType: MDXTokenType.Text, value: "", line: lexer.line, col: lexer.col)) # Handle missing '('
    else:
        tokens.add(MDXToken(tokenType: MDXTokenType.Text, value: "", line: lexer.line, col: lexer.col))  # Handle missing ']'
  return tokens

proc tokenizeUntil(lexer: var MDXLexer, endChar: char): MDXToken = # Helper for link text/url
    var value = ""
    while peek(lexer) != '\0' and peek(lexer) != endChar:
        value.add(peek(lexer))
        advance(lexer)
    MDXToken(tokenType: MDXTokenType.Text, value: value.strip(), line: lexer.line, col: lexer.col - len(value))


proc tokenize(lexer: var MDXLexer): seq[MDXToken] =
  while lexer.pos < len(lexer.input):
    skipWhitespace(lexer)
    case peek(lexer)
    of '\0': break
    of '`':
      if matchString(lexer, "```"):
        lexer.tokens.add(lexCodeBlock(lexer))
      else:
        lexer.tokens.add(lexInlineCode(lexer))
    of '*':
        if matchString(lexer, "**"):
            lexer.tokens.add(lexBold(lexer))
        else:
            lexer.tokens.add(lexItalic(lexer))
    of '[':
      lexer.tokens.add(lexLink(lexer))
    of '\n':
      lexer.tokens.add(MDXToken(tokenType: MDXTokenType.Newline, value: "\n", line: lexer.line, col: lexer.col))
      advance(lexer)
    else:
      lexer.tokens.add
