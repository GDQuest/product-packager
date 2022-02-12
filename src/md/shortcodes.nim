import std/
  [ strutils
  , sugar
  , tables
  ]
import parser


proc contentsShortcode(mdBlock: Block, mdBlocks: seq[Block]): seq[Block] =
  let
    levels = 2 .. (if mdBlock.args.len > 0: parseInt(mdBlock.args[0]) else: 3)
    headingToAnchor = proc(b: Block): string = b.heading.toLower.multiReplace({SPACE: "-", "'": "", "?": "", "!": ""})
    listBody = collect:
      for mdBlock in mdBlocks:
        if mdBlock.kind == bkHeading and mdBlock.level in levels:
          SPACE.repeat(2 * (mdBlock.level - 2)) & "- [" & mdBlock.heading & "](" & mdBlock.headingToAnchor & ")"

  @[ Paragraph(@["Contents:"])
   , Blank()
   , List(listBody)
   ]

const SHORTCODES* =
  { "contents": contentsShortcode
  }.toTable

