import std/[nre, strformat, strutils, tables, options, os, terminal]
import assets
import utils
import ../types
import ../image_size

type
  PatternHandler = object
    pattern: Regex
    handler: proc(match: RegexMatch, context: HandlerContext): string

  HandlerContext = object
    inputDirPath: string
    outputDirPath: string
    appSettings: AppSettingsBuildGDSchool

## Collects all error messages generated during the preprocessing of
## all files to group them at the end of the program's execution.
var preprocessorErrorMessages*: seq[string] = @[]

let
  regexAnchorLine = re"(?m)(?s)\h*(#|\/\/)\h*(ANCHOR|END).*?(\v|$)"

proc preprocessVideoFile(match: RegexMatch, context: HandlerContext): string =
  ## Replaces the relative input video path with an absolute path in the website's public directory.
  let
    captures = match.captures.toTable()
    src = captures["src"]
    before = captures.getOrDefault("before", " ").strip()
    after = captures.getOrDefault("after", " ").strip()
    outputPath = context.outputDirPath / src
  result = "<VideoFile " & before & " src=\"" & outputPath & "\"" & " " & after & "/>"

proc replaceGodotIcon(match: RegexMatch, context: HandlerContext): string =
  ## Replaces a Godot class name in inline code formatting with an icon component followed by the class name.
  ## TODO: replace with new icon component format.
  let className = match.captures.toTable()["class"].strip(chars = {'`'})
  if className in CACHE_GODOT_ICONS:
    result = "<IconGodot name=\"" & className & "\"/> " & match.match
  else:
    echo(fmt"Couldn't find icon for `{className}`. Skipping...")
    result = match.match

proc preprocessIncludeComponent(match: RegexMatch, context: HandlerContext): string =
  ## Replaces the Include shortcode with the contents of the section of a file or full file it points to.
  let args = match.captures.toTable()
  let includeFileName = cache.findCodeFile(args["file"])

  try:
    result = readFile(includeFileName)
    if "anchor" in args:
      let
        anchor = args["anchor"]
        regexAnchor = re(
          fmt(
            r"(?s)\h*(?:#|\/\/)\h*ANCHOR:\h*\b{anchor}\b\h*\v(?P<contents>.*?)\s*(?:#|\/\/)\h*END:\h*\b{anchor}\b"
          )
        )

      let anchorMatch = result.find(regexAnchor)
      if anchorMatch.isSome():
        let
          anchorCaptures = anchorMatch.get.captures.toTable()
          output = anchorCaptures["contents"]
          lines = output.splitLines()
        var prefixedLines: seq[string] = @[]

        # If we're in a code block, preserve indentation
        let prefix = args.getOrDefault("prefix", "")
        for line in lines:
          prefixedLines.add(prefix & line)
        result = prefixedLines.join("\n")
      else:
        let errorMessage =
          fmt"Can't find matching contents for anchor {anchor} in file {includeFileName}."
        stderr.styledWriteLine(fgRed, errorMessage)
        preprocessorErrorMessages.add(errorMessage)
        return match.match

    # Clean up anchor markers and extra newlines
    result = result.replace(regexAnchorLine, "").strip(chars = {'\n'})

  except IOError:
    let errorMessage =
      fmt"Failed to read include file: {includeFileName}"
    stderr.styledWriteLine(fgRed, errorMessage)
    preprocessorErrorMessages.add(errorMessage)
    return match.match

proc preprocessMarkdownImage(match: RegexMatch, context: HandlerContext): string =
  ## Replaces the relative input image path with an absolute path in the website's public directory.
  ## Also gives the image a class depending on its aspect ratio.
  let
    captures = match.captures.toTable()
    alt = captures["alt"].replace("\"", "'")
    relpath = captures["path"]
    outputPath = context.outputDirPath / relpath
    dimensions = getImageDimensions(context.inputDirPath / relpath)
  let
    ratio = dimensions.width / dimensions.height
    className =
      if ratio < 1.0: "portrait-image"
      elif ratio == 1.0: "square-image"
      else: "landscape-image"
  result = fmt"""<PublicImage src="{outputPath}" alt="{alt}" className="{className}" width="{dimensions.width}" height="{dimensions.height}"/>"""

const
  PATTERNS = {
    '`': @[
      PatternHandler(
        # TODO: add all node classes from assets module
        pattern: ["(`(?P<class>", CACHE_GODOT_BUILTIN_CLASSES.join("|"), ")`)"].join.re(),
        handler: replaceGodotIcon,
      )
    ],
    '<': @[
      PatternHandler(
        # Code include components
        pattern: re(
          r"""(?P<prefix>.*?)?< *Include\s+file=["'](?P<file>.+?\.[a-zA-Z0-9]+)["']\s*(?:anchor=["'](?P<anchor>\w+)["'])?\s*/>"""
        ),
        handler: preprocessIncludeComponent,
      ),
      PatternHandler(
        # Video file component
        pattern: re"""<VideoFile\s*(?P<before>.*?)?src=["'](?P<src>[^\"']+)["'](?P<after>.*?)?/>""",
        handler: preprocessVideoFile,
      )
    ],
    '!': @[
      PatternHandler(
        # Markdown images
        pattern: re"!\[(?P<alt>.*?)\]\((?P<path>.+?)\)",
        handler: preprocessMarkdownImage,
      )
    ]
  }.toTable()

proc processContent*(
    content: string,
    inputDirPath: string = "",
    outputDirPath: string = "",
    appSettings: AppSettingsBuildGDSchool,
): string =
  ## Runs through the content character by character, looking for patterns to replace.
  ## Once the first character of a pattern is found, it tries to match it with the regex patterns in the PATTERNS table.
  ## And if a regex is matched, it calls the handler function to replace the matched text with the new text.
  var
    i = 0
    lastMatchEnd = 0
    result = ""
    context = HandlerContext(
      inputDirPath: inputDirPath,
      outputDirPath: outputDirPath,
      appSettings: appSettings
    )

  while i < content.len:
    let currentChar = content[i]

    if currentChar in PATTERNS:
      var matched = false
      let patterns = PATTERNS[currentChar]

      for pattern in patterns:
        let match = content.match(pattern.pattern, i)

        if match.isSome:
          let matchObj = match.get()
          # Add the text between last match and current match
          result.add(content[lastMatchEnd ..< i])
          result.add(pattern.handler(matchObj, context))
          i += matchObj.match.len
          lastMatchEnd = i
          matched = true
          break

      if not matched:
        i += 1
    else:
      i += 1

  # Add remaining text after last match
  if lastMatchEnd < content.len:
    result.add(content[lastMatchEnd .. ^1])
