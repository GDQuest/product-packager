import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import honeycomb


type
  BlockKind* = enum
    bkBlank = "Blank",
    bkHeading = "Heading",
    bkCode = "Code",
    bkGDQuestShortcode = "GDQuestShortcode",
    bkImage = "Image",
    bkParagraph = "Paragraph",
    bkList = "List",
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
    of bkImage:
      alt*: string
      path*: string
    of bkGDQuestShortcode:
      name*: string
      args*: seq[string]
    of bkParagraph .. bkHTML:
      body*: seq[string]
    else: discard

  CodeLineKind* = enum
    clkRegular = "Regular",
    clkGDQuestShortcode = "GDQuestShortcode"

  CodeLine = object
    case kind*: CodeLineKind
    of clkGDQuestShortcode: gdquestShortcode*: Block
    of clkRegular: line*: string


func CodeRegular(line: string): CodeLine = CodeLine(kind: clkRegular, line: line)
func CodeGDQuestShortcode(gdquestShortcode: Block): CodeLine =
  if gdquestShortcode.kind != bkGDQuestShortcode:
    raise newException(ValueError, "Only bkGDQuestShortcode is allowed, but got {gdquestShortcode.kind}".fmt)
  CodeLine(kind: clkGDQuestShortcode, gdquestShortcode: gdquestShortcode)

func render*(b: Block): seq[string]

func render*(cl: CodeLine): string =
  case cl.kind
    of clkGDQuestShortcode: render(cl.gdquestShortcode).join
    of clkRegular: cl.line


func Blank(): Block = Block(kind: bkBlank)
func Heading(level: int, heading: string): Block = Block(kind: bkHeading, level: level, heading: heading)
func Code(language: string, code: seq[CodeLine]): Block = Block(kind: bkCode, language: language, code: code)
func Image(alt: string, path: string): Block = Block(kind: bkImage, alt: alt, path: path)
func GDQuestShortcode(name: string, args: seq[string]): Block = Block(kind: bkGDQuestShortcode, name: name, args: args)
func Paragraph(body: seq[string]): Block = Block(kind: bkParagraph, body: body)
func List(body: seq[string]): Block = Block(kind: bkList, body: body)
func BlockQuote(body: seq[string]): Block = Block(kind: bkBlockQuote, body: body)
func YAMLFrontMatter(body: seq[string]): Block = Block(kind: bkYAMLFrontMatter, body: body)
func Table(body: seq[string]): Block = Block(kind: bkTable, body: body)
func HTML(body: seq[string]): Block = Block(kind: bkHTML, body: body)

func render*(b: Block): seq[string] =
  case b.kind
    of bkBlank: @[""]
    of bkHeading: @['#'.repeat(b.level) & " " & b.heading]
    of bkCode: @["```" & b.language] & b.code.map(render) & @["```"]
    of bkImage: @["![" & b.alt & "](" & b.path & ")"]
    of bkGDQuestShortcode: @[(@["{%", b.name] & b.args & @["%}"]).join(" ")]
    of bkYAMLFrontMatter: @["---"] & b.body & @["---"]
    else: b.body


let
  newLine = regex(r"\R")
  nonNewLine = regex(r"\N")
  manySpaceOrTab = (c(' ') | c('\t')).many.join
  eol = manySpaceOrTab >> (newLine | eof)


let
  nonEmptyline = nonNewLine.atLeast(1).join << eol
  line = eol | nonEmptyline
  listLine = (manySpaceOrTab & regex(r"-|([a-z]|[0-9]|#)+\.") & nonEmptyline).join
  blockQuoteLine = (s(">") & manySpaceOrTab & nonEmptyline).join
  (codeOpenLine, codeCloseLine) = (s("```") >> nonNewLine.many.join << newLine, s("```") << eol)
  yamlOpenClose = (s("---") << eol)


let
  blank = eol.result(Blank())
  heading = ((c('#').atLeast(1) << manySpaceOrTab).join & nonEmptyline).map(x => Heading(x[0].len, x[1]))
  paragraph = nonEmptyline.atLeast(1).map(Paragraph)
  list = listLine.atLeast(1).map(List)
  blockQuote = blockQuoteLine.atLeast(1).map(BlockQuote)
  image = (
    s("![") >> ((nonNewLine << !c(']')).many & nonNewLine).optional.join &
    (s("](") >> ((nonNewLine << !c(')')).many & nonNewLine).join) << c(')') << eol
  ).map(x => Image(x[0], x[1]))

  gdquestShortcodeToken = ((alphanumeric | c("._")).many).join << manySpaceOrTab
  gdquestShortcode = (
    manySpaceOrTab >> s("{%") >> manySpaceOrTab >> gdquestShortcodeToken.atLeast(1) << s("%}") << eol
  ).map(x => GDQuestShortcode(x[0], x[1..^1].filter(x => x.len > 0)))

  lineToCodeLine = proc(x: string): CodeLine =
    if x.strip.startsWith("{%"): CodeGDQuestShortcode(gdquestShortcode.parse(x).value)
    else: CodeRegular(x.strip(false))
  code = (codeOpenLine & (line << !codeCloseLine).many & line << codeCloseLine).map(x => Code(x[0], x[1 .. ^1].map(lineToCodeLine)))

  yamlFrontMatter = (yamlOpenClose >> (line << !yamlOpenClose).many & (line << yamlOpenClose)).map(YAMLFrontMatter)
  table = (s("|") & line).join.atLeast(1).map(Table)
  html = (manySpaceOrTab & s("<") & line).join.atLeast(1).map(HTML)
  parser = (blank | yamlFrontMatter | code | heading | list | blockQuote | html | table | gdquestShortcode | image | paragraph).many


proc parse*(contents: string): seq[Block] =
    let parsed = parser.parse(contents)
    case parsed.kind
        of failure: stderr.writeLine(parsed.error)
        of success: return parsed.value
