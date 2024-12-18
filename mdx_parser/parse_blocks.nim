# The purpose of this pass is to chop the document into blocks, like headings,
# paragraphs, etc. This is done by looking at the first token of each line and
# determining what kind of block it is.
#
# TODO:
# - Next goal: complete paragraph parsing, then move on to inline parsing of MDX components and code blocks, then preprocessing and "rendering" the document as MDX.
# - Differentiate ranges of tokens from text ranges. Currently, it's confusing. Consider having two different types of ranges.
import parse_base_tokens
import shared

type
  BlockType* = enum
    Heading
    CodeBlock
    Paragraph
    UnorderedList
    OrderedList
    Blockquote

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
    of Paragraph, UnorderedList, OrderedList, Blockquote:
      discard

proc advanceToNewline(s: TokenScanner) {.inline.} =
  while not s.isAtEnd() and s.getCurrentToken().kind != Newline:
    s.current += 1

proc parseCodeBlock(s: TokenScanner): BlockToken =
  let start = s.current
  # Skip three backticks
  for i in 0..2:
    if s.peek(i).kind != Backtick:
      return nil
  s.current += 3

  # Language is in a text token following the backticks
  var languageRange = Range(start: 0, `end`: 0)
  if s.getCurrentToken().kind == Text:
    languageRange.start = s.getCurrentToken().range.start
    s.advanceToNewline()
    languageRange.end = s.getCurrentToken().range.end

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

  while not s.isAtEnd() and s.getCurrentToken().kind == Hash:
    level += 1
    s.current += 1

  s.advanceToNewline()
  return BlockToken(
    kind: Heading,
    range: Range(start: start, `end`: s.current),
    level: level,
  )

proc parseParagraph(s: TokenScanner): BlockToken =
  let start = s.current
  while not s.isAtEnd():
    if s.getCurrentToken().kind == Newline and s.peek(1).kind == Newline:
      s.current += 1
      break
    s.current += 1

  return BlockToken(
    kind: Paragraph,
    range: Range(start: start, `end`: s.current),
  )

proc parseMdxDocumentBlocks*(s: TokenScanner): seq[BlockToken] =
  # Parses blocks by checking the token at the start of a line (or of the document)
  # Algorithm:
  # - Check the token at the start of the line
  # - If it's a backtick, check if it's a code block
  # - If it's a dash, check if it's a heading
  #
  var blocks: seq[BlockToken]
  while not s.isAtEnd():
    let token = s.getCurrentToken()
    case token.kind:
      of Backtick:
        if s.peek(1).kind == Backtick and s.peek(2).kind == Backtick:
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

  case token.kind:
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
