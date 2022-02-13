import std/
  [ os
  , strformat
  , strutils
  , tables
  ]
import parser
import utils


proc linkShortcode(mdBlock: Block): string =
  try:
    let
      arg = mdBlock.args[0]
      name = findFile(if arg.endsWith(MD_EXT): arg else: arg & MD_EXT).splitFile.name
    fmt"[{name}](../{name}/{name}.html)"

  except ValueError:
    fmt"{mdBlock.render}: {getCurrentExceptionMsg()}".log
    mdBlock.render


const PARAGRAPH_SHORTCODES* =
  { "link": linkShortcode
  }.toTable

