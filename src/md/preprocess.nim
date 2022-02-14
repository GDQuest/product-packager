import std/
  [ sequtils
  , strutils
  , sugar
  , tables
  ]
import parser
import parserparagraph
import shortcodes
import utils


proc processParagraphLine(pl: seq[ParagraphLineSection], mdBlocks: seq[Block]): string =
  pl.mapIt(
    case it.kind
    of plskShortcode: SHORTCODES[it.shortcode.name](it.shortcode, mdBlocks)
    of plskRegular: it.render
  ).join(SPACE)


proc processCodeLine(cl: CodeLine, mdBlocks: seq[Block]): CodeLine =
  case cl.kind
  of clkShortcode: CodeLineRegular(SHORTCODES[cl.shortcode.name](cl.shortcode, mdBlocks))
  of clkRegular: cl


when isMainModule:
  const DIR = "../../godot-node-essentials/godot-project/"
  findFile = prepareFindFile(DIR, ["free-samples"])

  let
    mdBlocks = parse(readFile("./data/Line2D.md"))
    result = collect:
      for mdBlock in mdBlocks:
        case mdBlock.kind
        of bkShortcode:
          SHORTCODES[mdBlock.name](mdBlock, mdBlocks)

        of bkParagraph:
          mdBlock.body.mapIt(it.toParagraphLine.processParagraphLine(mdBlocks)).join(NL)

        of bkCode:
          Code(mdBlock.language, mdBlock.code.mapIt(it.processCodeLine(mdBlocks))).render

        else:
          mdBlock.render

  echo result.join(NL)
