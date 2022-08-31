import std/
  [ algorithm
  , logging
  , os
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


const
  META_MDFILE* = "_index.md"
  SERVER_DIR = "courses"

let
  regexGodotBuiltIns = ["(`(", CACHE_GODOT_BUILTIN_CLASSES.join("|"), ")`)"].join.re
  regexCapital = re"([23]D|[A-Z])"
  regexSlug = re"slug: *"

var cacheSlug: Table[string, seq[string]]


proc addGodotIcon(line: string): string =
  var
    line = line
    bounds = line.findBounds(regexGodotBuiltIns)

  while bounds != (-1, 0):
    let class = ["icon", line[bounds.first ..< bounds.last].strip(chars = {'`'}).replacef(regexCapital, "_$#")].join.toLower

    if class in CACHE_GODOT_ICONS:
      result.add [line[0 ..< bounds.first], "<Icon name=\"", class, "\"/>", line[bounds.first .. bounds.last]].join
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
      SHORTCODESv2.getOrDefault(it.shortcode.name, noOpShortcode)(it.shortcode, mdBlocks, fileName)
    of plskRegular: it.render
  ).join.addGodotIcon


func computeCodeBlockAnnotation(mdBlock: Block): string =
  for cl in mdBlock.code:
    if cl.kind == clkShortcode and cl.shortcode.name == "include" and cl.shortcode.args.len > 0:
      result = ":" & cl.shortcode.args[0]
      break


proc preprocessCodeLine(cl: CodeLine, mdBlocks: seq[Block]; fileName: string): string =
  case cl.kind
  of clkShortcode:
    SHORTCODESv2.getOrDefault(cl.shortcode.name, noOpShortcode)(cl.shortcode, mdBlocks, fileName)
  of clkRegular: cl.line


proc computeImageSlugs(fileName: string): seq[string] =
  if fileName in cacheSlug:
    return cacheSlug[fileName]

  for dir in fileName.parentDirs(inclusive = false):
    let meta_mdpath = dir / META_MDFILE
    if meta_mdpath.fileExists:
      for mdYAMLFrontMatter in readFile(meta_mdpath).parse.filterIt(it.kind == bkYAMLFrontMatter):
        for line in mdYAMLFrontMatter.body:
          if line.startsWith(regexSlug):
            result.add line.replace(regexSlug, "")

  result = result.reversed
  cacheSlug[fileName] = result


proc preprocessImage(img: Block, mdBlocks: seq[Block], fileName: string): string =
  var img = img
  img.path.removePrefix("./")
  img.path = (@["", SERVER_DIR] & computeImageSlugs(fileName) & img.path.split(AltSep)).join($AltSep)
  img.render


proc preprocessBlock(mdBlock: Block, mdBlocks: seq[Block]; fileName: string): string =
  case mdBlock.kind
  of bkShortcode:
    SHORTCODESv2.getOrDefault(mdBlock.name, noOpShortcode)(mdBlock, mdBlocks, fileName)

  of bkParagraph:
    mdBlock.body.mapIt(it.toParagraphLine.preprocessParagraphLine(mdBlocks, fileName)).join(NL)

  of bkList:
    mdBlock.items.mapIt(it.render.addGodotIcon).join(NL)

  of bkCode:
    [ fmt"```{mdBlock.language}" & computeCodeBlockAnnotation(mdBlock)
    , mdBlock.code.mapIt(it.preprocessCodeLine(mdBlocks, fileName)).join(NL)
    , "```"
    ].join(NL)
  
  of bkImage:
    mdBlock.preprocessImage(mdBlocks, fileName)

  else:
    mdBlock.render


proc preprocess*(fileName, contents: string): string =
  let mdBlocks = contents.parse
  mdBlocks.mapIt(preprocessBlock(it, mdBlocks, fileName)).join(NL)

