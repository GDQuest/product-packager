## Preprocesses MDX documents to replace markdown and some react components with other components and settings properties.
##
## The processContent() function is the main entry point for the preprocessor. You pass it the file's content, and it returns the processed content.
##
## The algorithm works like this:
##
## 1. It goes through the content character by character.
## 2. When it finds a character that matches a pattern, it tries to match the pattern with the regex patterns in a table.
## 3. If a regex is matched, it calls the corresponding preprocessing to replace the matched text with preprocessed text.
##
## See the proc processContent() for the list of patterns and their handlers.
import std/[nre, strformat, strutils, tables, options, os, terminal]
import assets
import utils
import ../settings
import ../image_size
when compileOption("profiler"):
  import std/nimprof

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

# Precompile regex patterns to avoid recompiling them in different functions
let
  regexAnchorLine = re"(?m)(?s)\h*(#|\/\/)\h*(ANCHOR|END).*?(\v|$)"
  regexVideoFile* =
    re"""(?s)<VideoFile\s*(?P<before>.*?)?src=["'](?P<src>[^\"']+)["'](?P<after>.*?)?/>"""
  regexMarkdownImage* = re"!\[(?P<alt>.*?)\]\((?P<path>.+?)\)"
  regexMDXName = re"^<\s*([A-Z][^\s>]+)"
  regexMDXAttr = re"""\s+([\w-]+)(?:=["']([^"']*)["'])?"""
  regexInclude = re(r"""<\s*Include.+?/>""")
  regexObjectPattern = re"\{.+?\}"
# This regex needs to be initialized after the assets.CACHE_GODOT_BUILTIN_CLASSES constant is defined.
var regexGodotIcon: Regex
# This table relies on the procs below and is initialized after them.
var patterns_table: Table[char, seq[PatternHandler]]

proc parseMDXComponent(componentText: string): ParsedMDXComponent =
  ## Parses an MDX component string into a ParsedMDXComponent object.
  result = ParsedMDXComponent(name: "", props: initTable[string, string]())

  let nameMatch = componentText.match(regexMDXName)
  if not nameMatch.isSome:
    raise newException(
      ValueError, "No valid component name found for string \"" & componentText & "\""
    )

  result.name = nameMatch.get.captures[0]
  for match in componentText.findIter(regexMDXAttr, nameMatch.get().matchBounds.b):
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
  result = "<VideoFile"
  if before.len > 0:
    result &= " " & before
  result &= " src=\"" & outputPath & "\""
  if after.len > 0:
    result.add(" " & after)
  result &= "/>"

proc preprocessGodotIcon(match: RegexMatch, context: HandlerContext): string =
  ## Replaces a Godot class name in inline code formatting with an icon component followed by the class name.
  # TODO: replace with new icon component format. -> https://github.com/GDQuest/product-packager/pull/74
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
  let file = args.getOrDefault("file", "")

  let includeFileName = utils.cache.findCodeFile(file)

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
          dedent =
            try:
              parseInt(args.getOrDefault("dedent", "0"))
            except:
              0

        for line in lines:
          var processedLine = line
          if dedent > 0:
            for i in 1 .. dedent:
              if processedLine.startsWith("\t"):
                processedLine = processedLine[1 ..^ 1]
          prefixedLines.add(prefix & processedLine)
        result = prefixedLines.join("\n")

        if "replace" in args:
          type SearchAndReplace = object
            source: string
            replacement: string

          # Parse the replace prop. It's a JSX expression with either a single object or an array of objects.
          # TODO: add error handling
          # TODO: this currently cannot work because the MDX component parsing cannot capture JSX expressions as props
          let replaces =
            try:
              # Remove the array mark if relevant, then parse objects - this should work
              # for both array and single object formats
              let replacesStr = args["replace"].strip(chars = {'[', ']'})
              let matches = replacesStr.findAll(regexObjectPattern)
              var searchesAndReplaces: seq[SearchAndReplace] = @[]

              for match in matches:
                var keyValuePairs = match.strip(chars = {'{', '}'}).split(",")
                var source, replacement: string

                for part in keyValuePairs:
                  let kv = part.strip().split(":")
                  if kv.len == 2:
                    let key = kv[0].strip().strip(chars = {'"'})
                    let value = kv[1].strip().strip(chars = {'"'})
                    if key == "source":
                      source = value
                    elif key == "replacement":
                      replacement = value

                searchesAndReplaces.add(
                  SearchAndReplace(source: source, replacement: replacement)
                )

              searchesAndReplaces
            except:
              @[]

          # Apply all replacements
          for searchAndReplace in replaces:
            result =
              result.replace(searchAndReplace.source, searchAndReplace.replacement)
      else:
        let errorMessage =
          fmt"Can't find matching contents for anchor {anchor} in file {includeFileName}."
        stderr.styledWriteLine(fgRed, errorMessage)
        preprocessorErrorMessages.add(errorMessage)
        return match.match

    # Clean up anchor markers and extra newlines
    result = result.replace(regexAnchorLine, "").strip(chars = {'\n'})
  except IOError:
    let errorMessage = fmt"Failed to read include file: {includeFileName}"
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
      if ratio < 1.0:
        "portrait-image"
      elif ratio == 1.0:
        "square-image"
      else:
        "landscape-image"
  result =
    fmt"""<PublicImage src="{outputPath}" alt="{alt}" className="{className}" width="{dimensions.width}" height="{dimensions.height}"/>"""

proc initializeRegexes(): Table[char, seq[PatternHandler]] =
  ## The table that maps chars to pattern handlers uses a proc to work around
  ## compile time expression evaluation, otherwise, the use of the regexGodotIcon
  ## would cause a compilation error as it depends on the
  ## CACHE_GODOT_BUILTIN_CLASSES constant.
  result = {
    '`':
      @[
        PatternHandler(
          # Builtin class names in inline code formatting, like `Node2D`
          pattern: regexGodotIcon,
          handler: preprocessGodotIcon,
        )
      ],
    '<':
      @[
        PatternHandler(
          # Code include components
          pattern: regexInclude,
          handler: preprocessIncludeComponent,
        ),
        PatternHandler(
          # Video file component
          pattern: regexVideoFile,
          handler: preprocessVideoFile,
        ),
      ],
    '!':
      @[
        PatternHandler(
          # Markdown images
          pattern: regexMarkdownImage,
          handler: preprocessMarkdownImage,
        )
      ],
  }.toTable()

regexGodotIcon =
  re("(`(?P<class>" & assets.CACHE_GODOT_BUILTIN_CLASSES.join("|") & ")`)")
patterns_table = initializeRegexes()

proc processContent*(
    content: string,
    inputDirPath: string = "",
    outputDirPath: string = "",
    appSettings: AppSettingsBuildGDSchool,
): string =
  ## Runs through the content character by character, looking for patterns to replace.
  ## Once the first character of a pattern is found, it tries to match it with the regex patterns in the patterns_table table.
  ## And if a regex is matched, it calls the handler function to replace the matched text with the new text.

  var
    i = 0
    lastMatchEnd = 0
    context = HandlerContext(
      inputDirPath: inputDirPath, outputDirPath: outputDirPath, appSettings: appSettings
    )

  while i < content.len:
    let currentChar = content[i]

    if currentChar in patterns_table:
      var matched = false
      let patterns = patterns_table[currentChar]

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
