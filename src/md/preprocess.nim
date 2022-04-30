import std/
  [ logging
  , re
  , sequtils
  , strformat
  , strutils
  , tables
  , unicode
  ]
import assets
import parser
import parserparagraph
import shortcodes
import utils


let regexGodotBuiltIns = ["(`(", CACHE_GODOT_BUILTIN_CLASSES.join("|"), ")`)"].join.re
let regexCapital = re"([23]D|[A-Z])"


proc addGodotIcon(line: string): string =
  var
    line = line
    bounds = line.findBounds(regexGodotBuiltIns)

  while bounds != (-1, 0):
    let class = ["icon", line[bounds.first ..< bounds.last].strip(chars = {'`'}).replacef(regexCapital, "_$#")].join.toLower

    if class in CACHE_GODOT_ICONS:
      result.add [line[0 ..< bounds.first], """<span class="godot-icon-class">""", CACHE_GODOT_ICONS[class], line[bounds.first .. bounds.last], "</span>"].join
    else:
      info fmt"Couldn't find icon for `{class}` in line: `{line}`. Skipping..."
      result.add line[0 .. bounds.last]

    line = line[bounds.last + 1 .. ^1]
    bounds = line.findBounds(regexGodotBuiltIns)

  result.add line


proc preprocessParagraphLine(pl: seq[ParagraphLineSection], mdBlocks: seq[Block]; fileName: string): string =
  pl.mapIt(
    case it.kind
    of plskShortcode:
      SHORTCODES.getOrDefault(it.shortcode.name, noOpShortcode)(it.shortcode, mdBlocks, fileName)
    of plskRegular: it.render
  ).join.addGodotIcon


proc preprocessCodeLine(cl: CodeLine, mdBlocks: seq[Block]; fileName: string): string =
  case cl.kind
  of clkShortcode:
    SHORTCODES.getOrDefault(cl.shortcode.name, noOpShortcode)(cl.shortcode, mdBlocks, fileName)
  of clkRegular: cl.line


proc preprocessBlock(mdBlock: Block, mdBlocks: seq[Block]; fileName: string): string =
  case mdBlock.kind
  of bkShortcode:
    SHORTCODES.getOrDefault(mdBlock.name, noOpShortcode)(mdBlock, mdBlocks, fileName)

  of bkParagraph:
    mdBlock.body.mapIt(it.toParagraphLine.preprocessParagraphLine(mdBlocks, fileName)).join(NL)

  of bkList:
    mdBlock.items.mapIt(it.render.addGodotIcon).join(NL)

  of bkCode:
    [ fmt"```{mdBlock.language}"
    , mdBlock.code.mapIt(it.preprocessCodeLine(mdBlocks, fileName)).join(NL)
    , "```"
    ].join(NL)

  else:
    mdBlock.render


proc preprocess*(fileName, contents: string): string =
  let mdBlocks = contents.parse
  mdBlocks.mapIt(preprocessBlock(it, mdBlocks, fileName)).join(NL)

