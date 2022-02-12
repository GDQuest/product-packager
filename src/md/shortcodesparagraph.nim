import std/
  [ os
  , sequtils
  , strformat
  , strutils
  , tables
  ]
import parser
import utils


proc linkShortcode(shortcode: Block): string =
  try:
    let
      arg = shortcode.args[0]
      name = findFile(if arg.endsWith(MD_EXT): arg else: arg & MD_EXT).splitFile.name
    fmt"[{name}](../{name}/{name}.html)"

  except ValueError:
    ( @[shortcode.render] &
      getCurrentExceptionMsg().splitLines
    ).mapIt(["[ERROR]", it].join(SPACE)).join(NL).quit


const PARAGRAPH_SHORTCODES* =
  { "link": linkShortcode
  }.toTable

