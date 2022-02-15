import std/
  [ sequtils
  , strformat
  , strutils
  , tables
  ]
import assets
import parser
import parserparagraph
import shortcodes


proc preprocessParagraphLine(pl: seq[ParagraphLineSection], mdBlocks: seq[Block]): string =
  pl.mapIt(
    case it.kind
    of plskShortcode: SHORTCODES[it.shortcode.name](it.shortcode, mdBlocks)
    of plskRegular: it.render
  ).join(SPACE)


proc preprocessCodeLine(cl: CodeLine, mdBlocks: seq[Block]): string =
  case cl.kind
  of clkShortcode: SHORTCODES[cl.shortcode.name](cl.shortcode, mdBlocks)
  of clkRegular: cl.line


proc preprocessBlock(mdBlock: Block, mdBlocks: seq[Block]): string =
  case mdBlock.kind
  of bkShortcode:
    SHORTCODES[mdBlock.name](mdBlock, mdBlocks)

  of bkParagraph:
    mdBlock.body.mapIt(it.toParagraphLine.preprocessParagraphLine(mdBlocks)).join(NL)

  of bkCode:
    [ fmt"```{mdBlock.language}"
    , mdBlock.code.mapIt(it.preprocessCodeLine(mdBlocks)).join(NL)
    , "```"
    ].join(NL)

  else:
    mdBlock.render


proc preprocess*(filename: string): string =
  let mdBlocks = parse(readFile(filename))
  mdBlocks.mapIt(preprocessBlock(it, mdBlocks)).join(NL)
