import parse_base_tokens

type
  BlockType* = enum
    Heading
    CodeBlock
    Paragraph
    #UnorderedList
    #OrderedList
    #Blockquote

  BlockToken* = ref object
    # Index range for the entire set of tokens corresponding to this block
    # Allows us to retrieve both the tokens and the source text from the first
    # and last token's ranges'
    range*: Range
    case kind*: BlockType
    of CodeBlock:
      language*: Range
      code*: Range
    of Heading:
      level*: int
      text*: Range
    of Paragraph:
      discard

proc parseCodeBlock(s: TokenScanner): BlockToken =
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

proc parseHeading(s: TokenScanner): BlockToken =
  let start = s.current
  var level = 0

  while not s.isAtEnd() and s.getCurrentToken().kind == Asterisk:
    level += 1
    s.current += 1

  # Must be followed by text
  if s.getCurrentToken().kind != Text:
    s.current = start
    return nil

  let textStart = s.current
  var textEnd = textStart

  # Find end of line
  while not s.isAtEnd():
    if s.getCurrentToken().kind == Newline:
      textEnd = s.current
      s.current += 1
      break
    s.current += 1

  return BlockToken(
    kind: Heading,
    range: Range(start: start, `end`: s.current),
    level: level,
    text: Range(start: textStart, `end`: textEnd)
  )

proc parseMdxDocumentBlocks*(s: TokenScanner): seq[BlockToken] =
  var blocks: seq[BlockToken]
  while not s.isAtEnd():
    let token = s.getCurrentToken()
    case token.kind:
      of Backtick:
        if s.peek(1).kind == Backtick and s.peek(2).kind == Backtick:
          let codeBlock = parseCodeBlock(s)
          if codeBlock != nil:
            blocks.add(codeBlock)
            continue
      of Asterisk:
        let headingBlock = parseHeading(s)
        if headingBlock != nil:
          blocks.add(headingBlock)
          continue
      else:
        discard
    s.current += 1
  result = blocks

proc echoBlockToken*(token: BlockToken, source: string, indent: int = 0) =
  echo "Block: ", $token.kind
  echo "Range:"
  echo "  Start: ", token.range.start
  echo "  End: ", token.range.end

  case token.kind:
    of CodeBlock:
      echo "Language: ", getString(token.language, source)
      echo "Code: ", getString(token.code, source)
    #of MdxComponent:
    #  echo "Name: ", getString(token.name, source)
    #  echo "Self closing: ", token.isSelfClosing
    #  if not token.isSelfClosing:
    #    echo "Opening tag range: ", token.openingTagRange.start, "..", token.openingTagRange.end
    #    echo "Body range: ", token.bodyRange.start, "..", token.bodyRange.end
    else:
      discard

proc echoBlockTokens*(tokens: seq[BlockToken], source: string) =
  echo "Parsed Block Tokens:"
  for token in tokens:
    echoBlockToken(token, source)
    echo ""
