## Program to preprocess markdown and MDX files for GDSchool.
## It find and replaces include shortcodes in code blocks and adds Godot icons
## for built-in class names in inline code marks.
import std /
  [logging
  , os
  , nre
  , strformat
  , strutils
  , tables
  , options
  ]
import assets
import utils


let
  regexShortcodeInclude = re"< *Include.+/>"
  regexMarkdownCodeBlock = re"(?m)(?s)```(?P<language>\w+?)?\n(?P<body>.+?)```"
  regexShortcodeArgsInclude = re(r"""< *Include file=["'](?P<file>.+?\.[a-zA-Z0-9]+)["'] *(anchor=["'](?P<anchor>\w+)["'])? *\/>""")
  regexGodotBuiltIns = ["(`(?P<class>", CACHE_GODOT_BUILTIN_CLASSES.join("|"),
      ")`)"].join.re()
  regexCapital = re"([23]D|[A-Z])"
  regexAnchorLine = re"(?m)(?s)\h*(#|\/\/)\h*(ANCHOR|END):.*?(\v|$)"
  regexVersionSuffix = re"(_v[0-9]+)"


proc preprocessCodeListings(content: string): string =
  ## Finds code blocks in the markdown document and searches for include
  ## shortcodes in each code block. If any include shortcode is found, appends
  ## the included file name to the code block and replaces include shortcodes
  ## with the corresponding code. Returns a new string.

  proc replaceIncludeShortcode(match: RegexMatch): string =
    ## Processes one include shortcode to replace. Finds and loads the
    ## appropriate GDScript or other code file and extracts and returns the
    ## contents corresponding to the requested anchor.
    let newMatch = match(match.match, regexShortcodeArgsInclude, 0, int.high)
    if newMatch.isSome():
      let
        args = newMatch.get.captures.toTable()
        includeFileName = cache.findFile(args["file"])
      result = readFile(includeFileName)
      if "anchor" in args:
        let
          anchor = args["anchor"]
          regexAnchor = re(fmt(r"(?s)\h*(?:#|\/\/)\h*ANCHOR:\h*\b{anchor}\b\h*\v(.*?)\s*(?:#|\/\/)\h*END:\h*\b{anchor}\b"))

        var anchorMatch = result.find(regexAnchor)
        if anchorMatch.isSome():
          result = anchorMatch.get.match
        else:
          raise newException(ValueError, "Can't find matching contents for anchor. {SYNOPSIS}")

      result = result.replace(regexAnchorLine, "")
    else:
      error ["Synopsis: `{{ include fileName(.gd|.shader) [anchorName] }}`"
        , fmt"{result}: Incorrect include arguments. Expected 1 or 2 arguments. Skipping..."
        ].join(NL)
      return match.match

  proc replaceMarkdownCodeBlock(match: RegexMatch): string =
    let parts = match.captures.toTable()
    let language = parts.getOrDefault("language", "gdscript")

    result = "```" & language

    let includeArgsMatch = find(parts["body"], regexShortcodeArgsInclude)
    if includeArgsMatch.isSome():
      let captures = includeArgsMatch.get.captures.toTable()
      result = result & ":" & captures["file"].replace(regexVersionSuffix, "")
      echo result
    result = result & "\n" & parts["body"].replace(regexShortcodeInclude,
        replaceIncludeShortcode) & "```"

  result = content.replace(regexMarkdownCodeBlock, replaceMarkdownCodeBlock)

proc addGodotIcons(content: string): string =
  proc replaceGodotIcon(match: RegexMatch): string =
    let className = match.captures.toTable()["class"]
    let cssClass = ["icon", className.strip(chars = {'`'}).replace(regexCapital,
        "_$#")].join().toLower()
    if cssClass in CACHE_GODOT_ICONS:
      result = "<Icon name=\"" & cssClass & "\"/>"
    else:
      info fmt"Couldn't find icon for `{cssClass}`. Skipping..."
      result = match.match

  result = content.replace(regexGodotBuiltIns, replaceGodotIcon)


proc processContent*(fileContent: string, fileName: string,
    pathPrefix = ""): string =
  const ROOT_SECTION_FOLDERS = @["courses", "bundles", "pages", "posts"]

  var prefix = pathPrefix
  if prefix == "":
    for folderName in ROOT_SECTION_FOLDERS:
      if folderName & AltSep in fileName:
        prefix = folderName
        break
    if prefix.isEmptyOrWhitespace():
      error fmt"The file {fileName} should be in one of the following folders: {ROOT_SECTION_FOLDERS}"

  result = fileContent.preprocessCodeListings().addGodotIcons()
