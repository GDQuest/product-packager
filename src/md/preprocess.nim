import std/algorithm
import std/os
import std/osproc
import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import std/tables
import fuzzy
import itertools
import honeycomb
import parser as p


const
  GD_EXT = ".gd"
  MD_EXT = ".md"

type
  ParagraphLineSectionKind = enum
    plskRegular,
    plskShortcode

  ParagraphLineSection = object
    case kind: ParagraphLineSectionKind
    of plskRegular: section: string
    of plskShortcode: shortcode: p.Block

  ParagraphLine = seq[ParagraphLineSection]

func ParagraphLineSectionRegular(section: string): ParagraphLineSection = ParagraphLineSection(kind: plskRegular, section: section)
func ParagraphLineSectionShortcode(shortcode: p.Block): ParagraphLineSection = ParagraphLineSection(kind: plskShortcode, shortcode: shortcode)

proc toParagraphLine(x: string): ParagraphLine =
  let parsed = (
    p.shortcodeSection.map(p.ShortcodeFromSeq).map(ParagraphLineSectionShortcode) |
    p.paragraphSection.map(ParagraphLineSectionRegular)
  ).many.parse(x)

  case parsed.kind
    of success: parsed.value
    else: @[]


var findFile: string -> string

proc prepareFindFile(dir: string, ignore: openArray[string] = []): string -> string =
  let (gitDir, exitCode) = execCmdEx("git rev-parse --show-toplevel", workingDir = dir)
  if exitCode != 0: ["[ERROR]", gitDir].join(p.SPACE).quit

  let
    cacheFiles = collect:
      for path in walkDirRec(gitDir.strip, relative = true):
        if (path.endsWith(GD_EXT) or
            path.endsWith(MD_EXT) and
            not ignore.any(x => path.startsWith(x))
        ): path

    cache = collect(
      for k, v in cacheFiles.groupBy(extractFilename): (k, v)
    ).toTable

  return func(name: string): string =
    if not (name in cache or name in cacheFiles):
      let candidates = cacheFiles
        .mapIt((score: name.fuzzyMatchSmart(it), path: it))
        .sorted((x, y) => cmp(x.score, y.score), SortOrder.Descending)[0 .. min(5, cacheFiles.len)]
        .mapIt(it.path)

      raise newException(ValueError, (
        @[ fmt"`{name}` doesnt exist. Check your path/name."
         , "First 5 possible candidates:" ] &
        candidates).join(p.NL))

    elif name in cache and cache[name].len != 1:
      raise newException(ValueError, (
        @[ fmt"`{name}` is associated with multiple files:"] &
           cache[name] &
           @["Use a file path in your shortcode instead."]).join(p.NL))

    elif name in cache:
      return cache[name][0]

    else:
      return name


func contentsShortcode(mdBlock: p.Block, mdBlocks: seq[p.Block]): seq[Block] =
  let
    levels = 2 .. (if mdBlock.args.len > 0: parseInt(mdBlock.args[0]) else: 3)
    headingToAnchor = proc(b: p.Block): string = b.heading.toLower.multiReplace({p.SPACE: "-", "'": ""}).strip(chars = {'?', '!'})

  @[ p.Paragraph(@["Contents:"])
   , p.Blank()
   , p.List(mdBlocks
     .filter(x => x.kind == p.bkHeading and x.level in levels)
     .map(x => ' '.repeat(2 * (x.level - 2)) & "- [" & x.heading & "](" & x.headingToAnchor & ")"))
   ]

const SHORTCODES =
  { "contents": contentsShortcode
  }.toTable


proc linkShortcode(shortcode: p.Block): string =
  try:
    let
      arg = shortcode.args[0]
      name = findFile(if arg.endsWith(MD_EXT): arg else: arg & MD_EXT).splitFile.name

    fmt"[{name}]({name}.html)"

  except ValueError:
    ( @[shortcode.render] &
      getCurrentExceptionMsg().splitLines
    ).map(x => ["[ERROR]", x].join(p.SPACE)).join(p.NL).quit

const PARAGRAPH_SHORTCODES =
  { "link": linkShortcode
  }.toTable


proc processParagraphLineSection(pls: ParagraphLineSection): string =
  case pls.kind
  of plskShortcode: PARAGRAPH_SHORTCODES[pls.shortcode.name](pls.shortcode)
  of plskRegular: pls.section


when isMainModule:
  const DIR = "../../godot-node-essentials/godot-project/"
  findFile = prepareFindFile(DIR, ["free-samples"])

  let mdBlocks = p.parse(readFile("./data/Line2D.md"))
  var result: seq[Block]
  for mdBlock in mdBlocks:
    case mdBlock.kind
    of p.bkShortcode:
      result &= SHORTCODES[mdBlock.name](mdBlock, mdBlocks)

    of p.bkParagraph:
      result.add Paragraph(
        mdBlock.body.map(
          x => x.toParagraphLine.map(processParagraphLineSection).join(p.SPACE)))

    else:
      result.add mdBlock

  echo result.map(p.render).join("\n")

# proc replaceIncludeShortcode(filename: string, anchor: string): string =
#   # TODO: Find file by filename, parse file and find content of anchor
#   return ""

# proc replaceLink(target: string, anchor: string = ""): string =
#   # TODO: check if target is name of file, if yes, ensure it's in cache
#   return ""

# proc generateTableOfContents(): string =
#   # TODO: check if target is name of file, if yes, ensure it's in cache
#   return ""

# proc replaceIconsInPlace(document: ProcessedMarkdown): ProcessedMarkdown =

#   proc appendImageToIcon(match: string): string =
#     #TODO: ensure it just trims the backticks
#     let className = match[1 .. -2]
#     # TODO: find image file path from class name
#     let
#       path = ""
#       basename = lastPathPart(path)
#     result = """<img src="{path}" alt="{basename}" />""".fmt & " " & match

#   var searchStartIndex = 0
#   var outputText = ""
#   while true:
#     let (start, last) = re.findBounds(document.text, RegexGDScriptClass, searchStartIndex)
#     if start < 0: break
#     outputText.add(document.text[searchStartIndex..<start])
#     # process the match in start, last
#     let match = document.text[start..last]
#     searchStartIndex = last + 1
#   #TODO: check that this does preserve errors in the `document`
#   outputText.add(document.text[searchStartIndex..len(document.text)])
#   result.text = outputText
#   return result

# # Finds patterns with the form {...} and passes them to the appropriate function
# # to replace the shortcode.
# # Returns the string with the shortcodes replaced.
# # TODO: keep track of line count for error reporting?
# proc replaceShortcodesInPlace(document: ProcessedMarkdown): ProcessedMarkdown =
#   let content = document.text
#   var
#     previousStartIndex = 0
#     shortcodeStartIndex = find(content, "{")
#   if shortcodeStartIndex == -1:
#     return ProcessedMarkdown(text: content, errors: @[])

#   while shortcodeStartIndex != -1:
#     result.text &= content[previousStartIndex..<shortcodeStartIndex]

#     let endIndex = find(content, "}", shortcodeStartIndex)
#     if endIndex == -1:
#       result.errors.add(Error(characterPosition: shortcodeStartIndex,
#           message: "Unterminated shortcode"))

#     # Parse and process supported shortcodes
#     let shortcode = content[shortcodeStartIndex .. endIndex]
#     var output = ""
#     let arguments = shortcode[1 .. -1].split(" ")
#     let shortcodeName = arguments[0]
#     case shortcodeName:
#       of "include":
#         if arguments.len() != 3:
#           result.errors.add(Error(
#               characterPosition: shortcodeStartIndex,
#               message: "Include shortcode requires two arguments: the path or name of the file to include from and the anchor's name."))
#           break
#         let
#           filename = arguments[1]
#           anchor = arguments[2]
#         output = replaceIncludeShortcode(filename, anchor)
#       of "link":
#         let argumentCount = arguments.len()
#         if argumentCount < 2:
#           result.errors.add(Error(
#               characterPosition: shortcodeStartIndex,
#               message: "Link shortcode requires at least one argument: the target file name or url."))
#           break
#         output = replaceLink(arguments[1])
#       of "table_of_contents":
#         if arguments.len() != 1:
#           result.errors.add(Error(
#               characterPosition: shortcodeStartIndex,
#               message: "Table of contents shortcode requires no arguments."))
#           break
#         output = generateTableOfContents()
#       else:
#         result.errors.add(Error(
#             characterPosition: shortcodeStartIndex,
#             message: "Unknown shortcode: " & shortcodeName))

#     result.text &= output
#     previousStartIndex = shortcodeStartIndex
#     shortcodeStartIndex = find(content, "{", endIndex + 1)

# proc runMarkdownPreprocessors*(content: string): ProcessedMarkdown =
#   ProcessedMarkdown(text: content, errors: @[]).replaceShortcodesInPlace().replaceIconsInPlace()

# # Calculates the line number for each error in the document. Modifies the line
# # numbers in-place.
# # To call on each document after collecting all errors during builds.
# proc setErrorLineNumbers*(document: ProcessedMarkdown) =
#   var
#     lineNumber = 1
#     lineStartIndex = 0
#     lineEndIndex = find(document.text, "\n", lineStartIndex)

#   let sortedErrors = sorted(document.errors, proc (a: Error, b: Error): int =
#     cmp(a.characterPosition, b.characterPosition))

#   for error in sortedErrors:
#     while error.characterPosition >= lineEndIndex:
#       lineStartIndex = lineEndIndex + 1
#       lineEndIndex = find(document.text, "\n", lineStartIndex)
#       lineNumber += 1
#     error.lineNumber = lineNumber
