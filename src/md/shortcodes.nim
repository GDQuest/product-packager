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


let regexAnchorLine* = r"\h*(#|\/\/)\h*(ANCHOR|END):.*?(\v|$)".re({reMultiLine, reDotAll})


proc contentsShortcode(mdBlock: Block, mdBlocks: seq[Block], fileName: string): string =
  const
    SYNOPSIS = "Synopsis: `{{ contents [maxLevel] }}`"
    DEFAULT_MAX_LEVEL = 3

  if mdBlock.args.len > 1:
    result = mdBlock.render
    error fmt"{SYNOPSIS}:"
    error [ fmt"{result}: Got `{mdBlock.args.len}` arguments, but expected 1 or less. Skipping..."
          ].join(SPACE)
    return result

  let
    levels = 2 .. (
      try:
        if mdBlock.args.len == 0: DEFAULT_MAX_LEVEL else: parseInt(mdBlock.args[0])

      except ValueError:
        error fmt"{SYNOPSIS}:"
        error [ fmt"{mdBlock.render}: Got `{mdBlock.args.join}`,"
              , "but expected integer argument."
              , fmt"Defaulting to `maxLevel = {DEFAULT_MAX_LEVEL}`."
              ].join(SPACE)
        DEFAULT_MAX_LEVEL
    )
    headingToAnchor = proc(b: Block): string = b.heading.toLower.multiReplace({SPACE: "-", "'": "", "?": "", "!": "", ":": ""})
    listItems = collect:
      for mdBlock in mdBlocks:
        if mdBlock.kind == bkHeading and mdBlock.level in levels:
          ListItem(form: spaces(2 * (mdBlock.level - 2)), item: fmt"- [{mdBlock.heading}](#{mdBlock.headingToAnchor})")

  if listItems.len == 0:
    result = mdBlock.render
    warn fmt"{result}: No valid headings found for ToC. Skipping..."

  else:
    result = @[ Paragraph(@["Contents:"])
              , Blank()
              , List(listItems)
              ].map(render).join(NL)


proc linkShortcode(mdBlock: Block, mdBlocks: seq[Block], fileName: string): string =
  const SYNOPSIS = "Synopsis: `{{ link fileName[.md] [text] }}`"
  if mdBlock.args.len == 0:
    result = mdBlock.render
    error [ fmt"{SYNOPSIS}:"
          , fmt"{result}: Got `{mdBlock.args.len}` arguments, but expected 1 or more. Skipping..." 
          ].join(NL)
    return result

  try:
    let
      argName = mdBlock.args[0]
      text = if mdBlock.args.len > 1: mdBlock.args[1 .. ^1].join(SPACE) else: argName.splitFile.name
      link = cache
        .findFile(argName & (if argName.endsWith(MD_EXT): "" else: MD_EXT))
        .replace(MD_EXT, HTML_EXT)
        .relativePath(fileName.parentDir, sep = '/')
    result = fmt"[{text}]({link})"

  except ValueError:
    result = mdBlock.render
    error [fmt"{result}: {getCurrentExceptionMsg()}", "{SYNOPSIS}. Skipping..."].join(NL)


proc includeShortcode(mdBlock: Block, mdBlocks: seq[Block], fileName: string): string =
  const SYNOPSIS = "Synopsis: `{{ include fileName(.gd|.shader) [anchorName] }}`"
  if mdBlock.args.len > 2:
    result = mdBlock.render
    error [ fmt"{SYNOPSIS}:"
          , fmt"{result}: Got `{mdBlock.args.len}` arguments, but expected 1 or 2. Skippinng..."
          ].join(NL)
    return result

  try:
    let
      argName = mdBlock.args[0]
      includeFileName = cache.findFile(argName)

    result = readFile(includeFileName)
    if mdBlock.args.len == 2:
      let
        argAnchor = mdBlock.args[1]
        regexAnchorContent = fmt"\h*(?:#|\/\/)\h*ANCHOR:\h*\b{argAnchor}\b\h*\v(.*?)\s*(?:#|\/\/)\h*END:\h*\b{argAnchor}\b".re({reDotAll})

      var matches: array[1, string]
      if not result.contains(regexAnchorContent, matches):
        raise newException(ValueError, "Can't find matching contents for anchor. {SYNOPSIS}")

      result = matches[0]
    result = result.replace(regexAnchorLine)

  except ValueError:
    result = mdBlock.render
    error [fmt"{result}: {getCurrentExceptionMsg()}.", fmt"{SYNOPSIS}. Skipping..."].join(NL)


proc noOpShortcode*(mdBlock: Block, mdBlocks: seq[Block], fileName: string): string =
  result = mdBlock.render
  # Temporary measure for `buildcoursev2` app so it doesn't output errors for { contents } & { link } shortcodes.
  if mdBlock.name notin ["contents", "link"]:
    error fmt"{result}: Got malformed shortcode. Skipping..."


const SHORTCODES* =
  { "include": includeShortcode
  , "link": linkShortcode
  , "contents": contentsShortcode
  }.toTable

const SHORTCODESv2* =
  { "include": includeShortcode
  }.toTable
