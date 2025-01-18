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
import std/[nre, strformat, strutils, tables, options, os, terminal, sets]
import godot_cached_data
import cache
import ../settings
import ../image_size
import ../gdscript/parser_gdscript
when compileOption("profiler"):
  import std/nimprof

type
  PatternHandler = ref object
    pattern: Regex
    handler: proc(match: RegexMatch, context: HandlerContext): string

  HandlerContext = ref object
    inputDirPath: string
    outputDirPath: string
    appSettings: BuildSettings

  ParsedMDXComponent = ref object
    name: string
    props: Table[string, string]

## Collects all error messages generated during the preprocessing of
## all files to group them at the end of the program's execution.
var preprocessorErrorMessages*: seq[string] = @[]

# Precompile regex patterns to avoid recompiling them in different functions
let
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
  ## Adds an IconGodot component for each Godot class name used in the markdown content, in inline code marks.
  ## For example, it transforms `Node` to <IconGodot name="Node" colorGroup="node">Node</IconGodot>.

  proc getGodotIconGroup(className: string): string =
    ## Returns the group of the Godot icon for the given class name.
    ## The group is used to color the icon in the same way as the Godot
    ## documentation.
    # TODO: complete the sets. Use compile time execution to build the editor category:
    # we can assume it's all icons that don't match a class in the godot/doc/classes folder.
    const CLASSES_ANIMATION = ["AnimationPlayer", "Tween", "AnimationTree"].toHashSet()
    const CLASSES_UI =
      ["Control", "ProgressBar", "HBoxContainer", "VBoxContainer"].toHashSet()
    const CLASSES_EDITOR =
      ["ToolMove", "ToolSelect", "ToolRotate", "ToolScale"].toHashSet()
    result =
      if className.endsWith("2D"):
        "2d"
      elif className.endsWith("3D"):
        "3d"
      elif className in CLASSES_ANIMATION:
        "animation"
      elif className in CLASSES_UI:
        "ui"
      elif className in CLASSES_EDITOR:
        "editor"
      elif className == "Node":
        "node"
      else:
        "general"

  let className = match.captures.toTable()["class"].strip(chars = {'`'})
  if className in CACHE_GODOT_ICONS:
    let group = getGodotIconGroup(className)
    result =
      fmt"""<IconGodot name="{className}" colorGroup="{group}">{className}</IconGodot>"""
  else:
    echo(fmt"Couldn't find icon for `{className}`. Skipping...")
    result = match.match

proc preprocessIncludeComponent(match: RegexMatch, context: HandlerContext): string =
  ## Processes the Include component, which includes code from a file. Uses the
  ## GDScript parser module to extract code from the file.
  ##
  ## The Include component can take the following props:
  ##
  ## - file: the name or project-relative path to the file to include
  ## - symbol: the symbol query to look for in the file, like a class name, a
  ## function name, etc. It also supports forms like ClassName.definition or
  ## ClassName.method_name.body
  ## - anchor: the anchor to look for in the file. You must use one of symbol or
  ## anchor, not both.
  ## - prefix: a string to add at the beginning of each line of the included
  ## code, typically + or - for diff code listings
  ## - dedent: the number of tabs to remove from the beginning of each line of the
  ## included code
  ## - replace: a JSX expression with an array of objects, each containing a source
  ## and replacement key. The source is the string to look for in the code, and the
  ## replacement is the string to replace it with.

  proc processSearchAndReplace(code: string, replaceJsxObject: string): string =
    ## Processes an include with a replace prop.
    ## It's a JSX expression with an array of objects, each containing a source and replacement key.
    type SearchAndReplace = object
      source: string
      replacement: string

    # Parse the replaceJsxObject prop. It's a JSX expression with either a single object or an array of objects.
    # TODO: add error handling
    # TODO: this currently cannot work because the MDX component parsing cannot capture JSX expressions as props
    # TODO: later: replace with MDX component parser
    var searchesAndReplaces: seq[SearchAndReplace] = @[]
    # Remove the array mark if relevant, then parse objects - this should work
    # for both array and single object formats
    let replacesStr = replaceJsxObject.strip(chars = {'[', ']'})
    let matches = replacesStr.findAll(regexObjectPattern)

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

    let replaces = searchesAndReplaces

    # Apply all replacements
    for searchAndReplace in replaces:
      result = result.replace(searchAndReplace.source, searchAndReplace.replacement)

  proc processCodeLines(code: string, prefix: string, dedent: int): string =
    ## Adds a prefix to each line of the code block and dedents it.
    var prefixedLines: seq[string] = @[]

    for line in code.splitLines():
      var processedLine = line
      if dedent > 0:
        for i in 1 .. dedent:
          if processedLine.startsWith("\t"):
            processedLine = processedLine[1 ..^ 1]
      prefixedLines.add(prefix & processedLine)
    result = prefixedLines.join("\n")

  let component = parseMDXComponent(match.match)
  let args = component.props
  let file = args.getOrDefault("file", "")
  let includeFilePath = cache.fileCache.findCodeFile(file)

  # TODO: error handling:
  # - if there's a replace prop, ensure it's correctly formatted
  # - warn about using anchor + symbol (one should take precedence)
  try:
    if "symbol" in args:
      let symbol = args.getOrDefault("symbol", "")
      if symbol == "":
        let errorMessage =
          fmt"Symbol prop is empty in include component for file {includeFilePath}. Returning an empty string."
        stderr.styledWriteLine(fgRed, errorMessage)
        preprocessorErrorMessages.add(errorMessage)
        return ""

      result = getCodeForSymbol(symbol, includeFilePath)
    elif "anchor" in args:
      let anchor = args.getOrDefault("anchor", "")
      if anchor == "":
        let errorMessage =
          fmt"Anchor prop is empty in include component for file {includeFilePath}. Returning an empty string."
        stderr.styledWriteLine(fgRed, errorMessage)
        preprocessorErrorMessages.add(errorMessage)
        return ""
      result = getCodeForAnchor(anchor, includeFilePath)
    else:
      result = getCodeWithoutAnchors(includeFilePath)

    # Add prefix and dedent the code block if applicable
    let
      prefix = args.getOrDefault("prefix", "")
      dedent =
        try:
          parseInt(args.getOrDefault("dedent", "0"))
        except:
          0

    if prefix != "" or dedent > 0:
      result = processCodeLines(result, prefix, dedent)
    if "replace" in args:
      result = processSearchAndReplace(result, args["replace"])
  except IOError:
    let errorMessage =
      fmt"Failed to read include file: {includeFilePath}. No code will be included."
    stderr.styledWriteLine(fgRed, errorMessage)
    preprocessorErrorMessages.add(errorMessage)
    result = ""

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

regexGodotIcon = (
  proc(): Regex =
    var pattern = "(`(?P<class>"
    for className in CACHE_GODOT_BUILTIN_CLASSES:
      pattern &= className & "|"
    pattern = pattern.strip(chars = {'|'}) & ")`)"
    return re(pattern)
)()
patterns_table = initializeRegexes()

proc processContent*(
    content: string,
    inputDirPath: string = "",
    outputDirPath: string = "",
    appSettings: BuildSettings,
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
