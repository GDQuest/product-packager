## This module contains the main logic for processing mdx content for GDSchool.
## It find and replaces include shortcodes in code blocks and adds Godot icons
## for built-in class names in inline code marks.
## Also, produces a css file with the list of all Godot icons used in the content.
import std/[logging, nre, strformat, strutils, tables, options, paths, os]
import assets
import utils
import ../types
import ../get_image_size

let
  regexShortcodeInclude = re"(?P<prefix>.*)< *Include.+/>"
  regexMarkdownCodeBlock = re"(?m)(?s)```(?P<language>[\w\-]+?)?\n(?P<body>.+?)```"
  regexShortcodeArgsInclude = re(
    r""".*< *Include file=["'](?P<file>.+?\.[a-zA-Z0-9]+)["'] *(anchor=["'](?P<anchor>\w+)["'])? *\/>"""
  )
  regexGodotBuiltIns =
    ["(`(?P<class>", CACHE_GODOT_BUILTIN_CLASSES.join("|"), ")`)"].join.re()
  regexAnchorLine = re"(?m)(?s)\h*(#|\/\/)\h*(region|endregion).*?(\v|$)"
  regexMarkdownImage = re"!\[(?P<alt>.*?)\]\((?P<path>.+?)\)"
  regexVideoFile =
    re("<VideoFile(?P<before>.*?)?src=[\"'](?P<src>[^\"']+)[\"'](?P<after>.*?)?/>")

proc preprocessCodeListings(content: string): string =
  ## Finds code blocks in the markdown document and searches for include
  ## shortcodes in each code block. If any include shortcode is found, appends
  ## the included file name to the code block and replaces include shortcodes
  ## with the corresponding code. Returns a new string.

  proc replaceIncludeShortcode(match: RegexMatch): string =
    ## Processes one include shortcode to replace. Finds and loads the
    ## appropriate GDScript or other code file and extracts and returns the
    ## contents corresponding to the requested anchor.

    let capturesTable = match.captures.toTable()
    let prefix = capturesTable.getOrDefault("prefix", "")
    let newMatch = match(match.match, regexShortcodeArgsInclude, 0, int.high)
    if newMatch.isSome():
      let
        args = newMatch.get.captures.toTable()
        includeFileName = cache.findCodeFile(args["file"])
      result = readFile(includeFileName)
      if "anchor" in args:
        let
          anchor = args["anchor"]
          regexAnchor = re(
            fmt(
              r"(?s)\h*(?:#|\/\/)\h*region\h*\b{anchor}\b\h*\v(?P<contents>.*?)\s*(?:#|\/\/)\h*endregion\h*\b{anchor}\b"
            )
          )

        var anchorMatch = result.find(regexAnchor)
        if anchorMatch.isSome():
          let anchorCaptures = anchorMatch.get.captures.toTable()
          let output = anchorCaptures["contents"]
          let lines = output.splitLines()
          var prefixedLines: seq[string] = @[]
          for line in lines:
            prefixedLines.add(prefix & line)
          result = prefixedLines.join("\n")
        else:
          raise newException(
            ValueError,
            fmt"Can't find matching contents for anchor {anchor} in file {includeFileName}.",
          )

      result = result.replace(regexAnchorLine, "").strip(chars = {'\n'})
    else:
      error [
        "Synopsis: `<Include file='fileName(.gd|.shader)' [anchor='anchorName'] />`",
        fmt"{result}: Incorrect include arguments. Expected 1 or 2 arguments. Skipping...",
      ].join(NL)
      return match.match

  proc replaceMarkdownCodeBlock(match: RegexMatch): string =
    let parts = match.captures.toTable()
    let language = parts.getOrDefault("language", "gdscript")

    result = "```" & language

    result =
      result & "\n" &
      parts["body"].replace(regexShortcodeInclude, replaceIncludeShortcode) & "```"

  result = content.replace(regexMarkdownCodeBlock, replaceMarkdownCodeBlock)

## Appends a react component for each Godot class name used in the markdown content, in inline code marks.
## For example, it transforms `Node` to <IconGodot name="Node"/>.
proc addGodotIcons(content: string): string =
  proc replaceGodotIcon(match: RegexMatch): string =
    let className = match.captures.toTable()["class"].strip(chars = {'`'})
    if className in CACHE_GODOT_ICONS:
      result = "<IconGodot name=\"" & className & "\"/> " & match.match
    else:
      info fmt"Couldn't find icon for `{className}`. Skipping..."
      result = match.match

  result = content.replace(regexGodotBuiltIns, replaceGodotIcon)

proc replaceMarkdownImages*(
    content: string, outputDirPath: string, inputDirPath: string
): string =
  proc replaceOneImage(match: RegexMatch): string =
    let
      captures = match.captures.toTable()
      alt = captures["alt"]
      relpath = captures["path"]
      outputPath = outputDirPath / relpath
      dimensions = getImageDimensions(inputDirPath / relpath)

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

  result = content.replace(regexMarkdownImage, replaceOneImage)

proc replaceVideos*(content: string, outputDirPath: string): string =
  proc replaceOneVideo(match: RegexMatch): string =
    let
      captures = match.captures.toTable()
      src = captures["src"]
      before = captures.getOrDefault("before", " ")
      after = captures.getOrDefault("after", " ")
      outputPath = outputDirPath / src
    result = fmt"""<VideoFile{before}src="{outputPath}"{after}/>"""

  result = content.replace(regexVideoFile, replaceOneVideo)

proc processContent*(
    fileContent: string,
    inputFilePath: string = "",
    appSettings: AppSettingsBuildGDSchool,
): string =
  let inputDirPath = Path(inputFilePath).parentDir()
  let publicDir = inputDirPath.string().replace(appSettings.contentDir, "/")
  result = fileContent
    .preprocessCodeListings()
    .replaceMarkdownImages(publicDir, inputDirPath.string())
    .replaceVideos(publicDir)
    .addGodotIcons()
