## The purpose of this pass is to chop the document into blocks, like headings,
## paragraphs, etc. This is done by looking at the first token of each line and
## determining what kind of block it is.
#
# TODO:
# - Next goal: complete paragraph parsing, then move on to inline parsing of MDX components and code blocks, then preprocessing and "rendering" the document as MDX.
# - Differentiate ranges of tokens from text ranges. Currently, it's confusing. Consider having two different types of ranges.
import parse_base_tokens
import shared

const THREE_BACKTICKS = @[Backtick, Backtick, Backtick]

type
  BlockType* = enum
    Heading
    CodeBlock
    Paragraph
    UnorderedList
    OrderedList
    Blockquote

  BlockToken* = Token[BlockType]
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
    of Paragraph, UnorderedList, OrderedList, Blockquote:
      discard

proc stripTokenText(token: LexerToken, source: string, characters: set[char]): Range =
  var newStart = token.range.start
  while newStart < token.range.end and source[newStart] in characters:
    newStart += 1

  var newEnd = token.range.end
  while newEnd > newStart and source[newEnd - 1] in characters:
    newEnd -= 1

  result = Range(start: newStart, `end`: newEnd)

proc parseCodeBlock(s: TokenScanner): BlockToken =
  let start = s.current
  # Skip the three backticks
  s.current += 3

  # After the three backticks, if there is a text token, we assume it's the
  # language and try to extract it.
  var languageRange = Range(start: 0, `end`: 0)
  if s.currentToken.kind == Text:
    languageRange = s.currentToken.stripTokenText(s.source, {' ', '\t'})
    if languageRange.start == languageRange.end:
      stderr.writeLine("Error: No language found for code block at line ", s.current)

  s.advanceToNextLineStart()

  let codeStart = s.current
  var codeEnd = codeStart
  # Find closing backticks, everything in between is code
  while not s.isAtEnd():
    if s.isPeekSequence(THREE_BACKTICKS):
      # The code ends before the closing backticks
      codeEnd = s.current - 1
      s.current += 3
      break
    s.current += 1

  return BlockToken(
    kind: CodeBlock,
    range: Range(start: start, `end`: s.current),
    language: languageRange,
    code: Range(start: codeStart, `end`: codeEnd),
  )

proc parseHeading(s: TokenScanner): BlockToken =
  let start = s.current
  var level = 0

  while not s.isAtEnd() and s.currentToken.kind == Hash:
    level += 1
    s.current += 1

  let textStart = s.current
  s.advanceToNewline()

  return BlockToken(
    kind: Heading,
    range: Range(start: start, `end`: s.current),
    level: level,
    text: Range(start: textStart, `end`: s.current),
  )

proc parseParagraph(s: TokenScanner): BlockToken =
  let start = s.current
  while not s.isAtEnd():
    if s.currentToken.kind == Newline and s.peek(1).kind == Newline:
      s.current += 1
      break
    s.current += 1

  return BlockToken(kind: Paragraph, range: Range(start: start, `end`: s.current))

proc parseMdxDocumentBlocks*(s: TokenScanner): seq[BlockToken] =
  # Parses blocks by checking the token at the start of a line (or of the document)
  # Algorithm:
  # - Check the token at the start of the line
  # - If it's a backtick, check if it's a code block
  # - If it's a dash, check if it's a heading
  #
  var blocks: seq[BlockToken]
  while not s.isAtEnd():
    let token = s.currentToken
    case token.kind
    of Backtick:
      if s.isPeekSequence(THREE_BACKTICKS):
        let codeListing = parseCodeBlock(s)
        if codeListing != nil:
          blocks.add(codeListing)
          continue
    of Hash:
      let heading = parseHeading(s)
      if heading != nil:
        blocks.add(heading)
        continue
      else:
        let paragraph = parseParagraph(s)
        if paragraph != nil:
          blocks.add(paragraph)
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

  case token.kind
  of CodeBlock:
    echo "Language: ", getString(token.language, source)
    echo "Code: ", getString(token.code, source)
  of Paragraph, UnorderedList, OrderedList, Blockquote, Heading:
    echo "Text: ", getString(token.text, source)
    #of MdxComponent:
    #  echo "Name: ", getString(token.name, source)
    #  echo "Self closing: ", token.isSelfClosing
    #  if not token.isSelfClosing:
    #    echo "Opening tag range: ", token.openingTagRange.start, "..", token.openingTagRange.end
    #    echo "Body range: ", token.bodyRange.start, "..", token.bodyRange.end

proc echoBlockTokens*(tokens: seq[BlockToken], source: string) =
  echo "Parsed Block Tokens:"
  for token in tokens:
    echoBlockToken(token, source)
    echo ""
