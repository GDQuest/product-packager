import honeycomb
import parser


type
  ParagraphLineSectionKind* = enum
    plskRegular,
    plskShortcode

  ParagraphLineSection* = object
    case kind*: ParagraphLineSectionKind
    of plskRegular: section*: string
    of plskShortcode: shortcode*: Block

func render*(pls: ParagraphLineSection): string =
  case pls.kind
  of plskShortcode: pls.shortcode.render
  of plskRegular: pls.section

func ParagraphLineSectionRegular(section: string): ParagraphLineSection = ParagraphLineSection(kind: plskRegular, section: section)
func ParagraphLineSectionShortcode(shortcode: Block): ParagraphLineSection = ParagraphLineSection(kind: plskShortcode, shortcode: shortcode)

proc toParagraphLine*(x: string): seq[ParagraphLineSection] =
  let parsed = (
    shortcodeSection.map(ShortcodeFromSeq).map(ParagraphLineSectionShortcode) |
    paragraphSection.map(ParagraphLineSectionRegular)
  ).many.parse(x)

  case parsed.kind
    of success: parsed.value
    else: @[]

