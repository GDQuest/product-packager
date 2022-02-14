import std/
  [ logging
  , re
  , os
  , sequtils
  , strformat
  , strutils
  , sugar
  , tables
  ]
import parser
import utils


proc contentsShortcode(mdBlock: Block, mdBlocks: seq[Block]): string =
  try:
    let
      levels = 2 .. (if mdBlock.args.len > 0: parseInt(mdBlock.args[0]) else: 3)
      headingToAnchor = proc(b: Block): string = b.heading.toLower.multiReplace({SPACE: "-", "'": "", "?": "", "!": ""})
      listBody = collect:
        for mdBlock in mdBlocks:
          if mdBlock.kind == bkHeading and mdBlock.level in levels:
            SPACE.repeat(2 * (mdBlock.level - 2)) & "- [" & mdBlock.heading & "](" & mdBlock.headingToAnchor & ")"

    if listBody.len == 0:
      raise newException(ValueError, fmt"No valid headings found for ToC. Skipping...")

    @[Paragraph(@["Contents:"]), Blank(), List(listBody)].map(render).join(NL)

  except ValueError:
    fmt"{mdBlock.render}: {getCurrentExceptionMsg()}".warn
    mdBlock.render


proc linkShortcode(mdBlock: Block, mdBlocks: seq[Block]): string =
  try:
    let
      argName = mdBlock.args[0]
      name = findFile(argName & (if argName.endsWith(MD_EXT): "" else: MD_EXT)).splitFile.name
    fmt"[{name}](../{name}/{name}.html)"

  except ValueError:
    fmt"{mdBlock.render}: {getCurrentExceptionMsg()}".error
    mdBlock.render


proc includeShortcode(mdBlock: Block, mdBlocks: seq[Block]): string =
  try:
    if mdBlock.args.len != 2:
      raise newException(ValueError, fmt"Got {mdBlock.args.len} arguments, but expected 2. Skipping...")

    var matches = [""]
    let
      (argName, argAnchor) = (mdBlock.args[0], mdBlock.args[1])
      fileName = findFile(argName & (if argName.endsWith(GD_EXT): "" else: GD_EXT))
      regexAnchor = fmt"\h*#\h*ANCHOR:\h*{argAnchor}\s*(.*?)\s*#\h*END:\h*{argAnchor}".re({reDotAll})
      fileContents = readFile(fileName)

    if not fileContents.contains(regexAnchor, matches):
      raise newException(ValueError, "Can't find matching contents for anchor. Skipping...")

    matches[0]

  except ValueError:
    fmt"{mdBlock.render}: {getCurrentExceptionMsg()}".error
    mdBlock.render


const SHORTCODES* =
  { "include": includeShortcode
  , "link": linkShortcode
  , "contents": contentsShortcode
  }.toTable

