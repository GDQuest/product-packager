import std/
  [ logging
  , sequtils
  , strutils
  , sugar
  ]
import honeycomb
import utils


type
  BlockKind* = enum
    bkBlank = "Blank",
    bkHeading = "Heading",
    bkCode = "Code",
    bkShortcode = "Shortcode",
    bkImage = "Image",
    bkList = "List",
    bkParagraph = "Paragraph",
    bkBlockQuote = "BlockQuote",
    bkYAMLFrontMatter = "YAMLFrontMatter",
    bkTable = "Table",
    bkHTML = "HTML"

  Block* = object
    case kind*: BlockKind
    of bkHeading:
      level*: int
      heading*: string
    of bkCode:
      language*: string
      code*: seq[CodeLine]
    of bkShortcode:
      name*: string
      args*: seq[string]
    of bkImage:
      alt*: string
      path*: string
    of bkList:
      items*: seq[ListItem]
    of bkParagraph .. bkHTML:
      body*: seq[string]
    else: discard

  CodeLineKind* = enum
    clkRegular = "Regular",
    clkShortcode = "Shortcode"

  CodeLine* = object
    case kind*: CodeLineKind
    of clkShortcode: shortcode*: Block
    of clkRegular: line*: string

  ListItem* = object
    form*: string
    item*: string

func render*(b: Block): string

func CodeLineRegular*(line: string): CodeLine = CodeLine(kind: clkRegular, line: line)
func CodeLineShortcode*(shortcode: Block): CodeLine = CodeLine(kind: clkShortcode, shortcode: shortcode)

func render*(cl: CodeLine): string =
  case cl.kind
    of clkShortcode: cl.shortcode.render
    of clkRegular: cl.line

func render*(li: ListItem): string = [li.form, li.item].join(SPACE)


func Blank*(): Block = Block(kind: bkBlank)
func Heading*(level: int, heading: string): Block = Block(kind: bkHeading, level: level, heading: heading.strip)
func Code*(language: string, code: seq[CodeLine]): Block = Block(kind: bkCode, language: if language.strip == "": "gdscript" else: language, code: code)
func Image*(alt: string, path: string): Block = Block(kind: bkImage, alt: alt, path: path)
func Shortcode*(name: string, args: seq[string]): Block = Block(kind: bkShortcode, name: name, args: args)
func ShortcodeFromSeq*(x: seq[string]): Block =
  if x.len == 0: Shortcode("", @[]) else: Shortcode(x[0], x[1..^1])
func List*(items: seq[ListItem]): Block = Block(kind: bkList, items: items)
func Paragraph*(body: seq[string]): Block = Block(kind: bkParagraph, body: body)
func BlockQuote*(body: seq[string]): Block = Block(kind: bkBlockQuote, body: body)
func YAMLFrontMatter*(body: seq[string]): Block = Block(kind: bkYAMLFrontMatter, body: body)
func Table*(body: seq[string]): Block = Block(kind: bkTable, body: body)
func HTML*(body: seq[string]): Block = Block(kind: bkHTML, body: body)

func render*(b: Block): string =
  case b.kind
    of bkBlank: ""
    of bkHeading: '#'.repeat(b.level) & SPACE & b.heading
    of bkCode: (@["```" & b.language] & b.code.map(render) & @["```"]).join(NL)
    of bkImage: "![" & b.alt & "](" & b.path & ")"
    of bkShortcode: ["{{", (@[b.name] & b.args).join(SPACE), "}}"].join(SPACE)
    of bkList: b.items.map(render).join(NL)
    of bkYAMLFrontMatter: (@["---"] & b.body & @["---"]).join(NL)
    else: b.body.join(NL)


let
  newLine = regex(r"\R")
  nonNewLine = regex(r"\N")
  manySpaceOrTab = (c(' ') | c('\t')).many.join
  eol = manySpaceOrTab >> (newLine | eof)


let
  nonEmptyLine = (nonNewLine.atLeast(1).join << eol).map(x => x.strip(leading = false))
  line = eol | nonEmptyLine
  listStart = (manySpaceOrTab & regex(r"-\h+?|([a-z]|[0-9]|#)+\.\h+?").map(x => x.strip)).join
  listItem = (listStart & nonEmptyLine & (!listStart >> manySpaceOrTab >> nonEmptyLine).many).map(x => ListItem(form: x[0], item: x[1 .. ^1].join(SPACE)))
  blockQuoteLine = (s(">") & manySpaceOrTab & nonEmptyLine).join
  (codeOpenLine, codeCloseLine) = (s("```") >> nonNewLine.many.join << newLine, s("```") << eol)
  yamlOpenClose = (s("---") << eol)


let
  blank = eol.result(Blank())
  heading = ((c('#').atLeast(1).join << manySpaceOrTab) & nonEmptyLine).map(x => Heading(x[0].len, x[1]))
  list = listItem.atLeast(1).map(List)
  blockQuote = blockQuoteLine.atLeast(1).map(BlockQuote)
  image = (
    s("![") >> ((nonNewLine << !c(']')).many & nonNewLine).optional.join &
    (s("](") >> ((nonNewLine << !c(')')).many & nonNewLine).join) << c(')') << eol
  ).map(x => Image(x[0], x[1]))

  shortcodeToken = manySpaceOrTab >> (alphanumeric | c(r"./\-_")).many.join << manySpaceOrTab
  shortcodeSection* = (s("{%") | s("{{")) >> (shortcodeToken.atLeast(1).filter(x => x.len > 0)) << manySpaceOrTab << (s("%}") | s("}}"))
  shortcode = manySpaceOrTab >> shortcodeSection.map(ShortcodeFromSeq) << eol

  paragraphSection* = ((nonNewLine << !(s("{%") | s("{{"))).many & manySpaceOrTab).join
  paragraph = nonEmptyLine.atLeast(1).map(Paragraph)

  lineToCodeLine = proc(x: string): CodeLine =
    let parsed = shortcode.parse(x)
    case parsed.kind
    of success: CodeLineShortcode(parsed.value)
    of failure: CodeLineRegular(x.strip(leading = false))
  code = (codeOpenLine & (line << !codeCloseLine).many & line << codeCloseLine).map(x => Code(x[0], x[1 .. ^1].map(lineToCodeLine)))

  yamlFrontMatter = (yamlOpenClose >> (line << !yamlOpenClose).many & (line << yamlOpenClose)).map(YAMLFrontMatter)
  table = (s("|") & line).join.atLeast(1).map(Table)
  html = (manySpaceOrTab & s("<") & line).join.atLeast(1).map(HTML)
  parser = (blank | yamlFrontMatter | code | heading | list | blockQuote | html | table | shortcode | image | paragraph).many


proc parse*(contents: string): seq[Block] =
    let parsed = parser.parse(contents)
    case parsed.kind
        of failure: error parsed.error
        of success: return parsed.value

