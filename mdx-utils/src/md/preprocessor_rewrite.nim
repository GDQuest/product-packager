import std/[nre, strformat, strutils, tables, options, os, terminal]
import assets
import utils
import ../types
import ../image_size

type
  PatternHandler = ref object
    pattern: Regex
    handler: proc(match: RegexMatch, context: HandlerContext): string

  HandlerContext = ref object
    inputDirPath: string
    outputDirPath: string
    appSettings: AppSettingsBuildGDSchool

  ParsedMDXComponent = ref object
    name: string
    props: Table[string, string]


## Collects all error messages generated during the preprocessing of
## all files to group them at the end of the program's execution.
var preprocessorErrorMessages*: seq[string] = @[]

let
  regexAnchorLine = re"(?m)(?s)\h*(#|\/\/)\h*(ANCHOR|END).*?(\v|$)"

proc parseMDXComponent(componentText: string): ParsedMDXComponent =
  ## Parses an MDX component string into a ParsedMDXComponent object.
  result = ParsedMDXComponent(
    name: "",
    props: initTable[string, string]()
  )

  let namePattern = re"^<\s*([A-Z][^\s>]+)"
  let attrPattern = re"""\s+([\w-]+)(?:=["']([^"']*)["'])?"""

  let nameMatch = componentText.match(namePattern)
  if not nameMatch.isSome:
    raise newException(ValueError, "No valid component name found for string \"" & componentText & "\"")

  result.name = nameMatch.get.captures[0]
  for match in componentText.findIter(attrPattern, nameMatch.get().matchBounds.b):
    let name = match.captures[0]
    let value = match.captures[1]
    result.props[name] = value

proc preprocessVideoFile(match: RegexMatch, context: HandlerContext): string =
  ## Replaces the relative input video path with an absolute path in the website's public directory.
  let
    captures = match.captures.toTable()
    src = captures["src"]
    before = captures.getOrDefault("before", " ").strip()
    after = captures.getOrDefault("after", " ").strip()
    outputPath = context.outputDirPath / src
  result = "<VideoFile " & before & " src=\"" & outputPath & "\"" & " " & after & "/>"

proc preprocessGodotIcon(match: RegexMatch, context: HandlerContext): string =
  ## Replaces a Godot class name in inline code formatting with an icon component followed by the class name.
  ## TODO: replace with new icon component format. -> https://github.com/GDQuest/product-packager/pull/74
  let className = match.captures.toTable()["class"].strip(chars = {'`'})
  if className in CACHE_GODOT_ICONS:
    result = "<IconGodot name=\"" & className & "\"/> " & match.match
  else:
    echo(fmt"Couldn't find icon for `{className}`. Skipping...")
    result = match.match

proc preprocessIncludeComponent(match: RegexMatch, context: HandlerContext): string =
  ## Replaces the Include shortcode with the contents of the section of a file or full file it points to.
  let component = parseMDXComponent(match.match)
  let args = component.props

  let includeFileName = cache.findCodeFile(args["file"])

  # TODO: Replace with gdscript parser, get symbols or anchors from the parser:
  # TODO: add support for symbol prop
  # TODO: replace prefixes in lesson material with include prop
  # TODO: error handling:
    # - if there's a replace prop, ensure it's correctly formatted
    # - warn about using anchor + symbol (one should take precedence)
    # - check that prefix is valid (- or +)
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

        # Add prefix and dedent the code block if applicable
        let
          prefix = args.getOrDefault("prefix", "")
          dedent = try: parseInt(args.getOrDefault("dedent", "0")) except: 0

        for line in lines:
          var processedLine = line
          if dedent > 0:
            for i in 1..dedent:
              if processedLine.startsWith("\t"):
                processedLine = processedLine[1..^1]
          prefixedLines.add(prefix & processedLine)
        result = prefixedLines.join("\n")

        if "replace" in args:
          let replace = args["replace"]
          result = result.replace(replace, args["with"])
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
    result = match.match

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
        handler: preprocessGodotIcon,
      )
    ],
    '<': @[
      PatternHandler(
        # Code include components
        pattern: re(
          r"""<\s*Include.+?/>"""
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
