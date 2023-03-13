import std/
  [ algorithm
  , logging
  , os
  , nre
  , strformat
  , strutils
  , tables
  , options
  ]
import assets
import utils


var cacheSlug: Table[string, seq[string]]

let
  regexShortcodeInclude = re"{{ *include.+}}"
  regexMarkdownImage = re"!\[(?P<alt>.*)\]\((?P<path>.+)\)"
  regexHtmlImage = re"""<\s*img.+src="(?P<path>.+?)".*\/>"""
  regexMarkdownCodeBlock = re"(?m)(?s)```(?P<language>\w+?)?\n(?P<body>.+?)```"
  regexShortcodeArgsInclude = re"{{ *include (?P<file>.+?\.[a-zA-Z0-9]+) *(?P<anchor>\w+)? *}}"
  regexGodotBuiltIns = ["(`(?P<class>", CACHE_GODOT_BUILTIN_CLASSES.join("|"), ")`)"].join.re
  regexCapital = re"([23]D|[A-Z])"
  regexAnchorLine = re"(?m)(?s)\h*(#|\/\/)\h*(ANCHOR|END):.*?(\v|$)"

  regexDownloads = re"(?m)(?s)<Downloads .+?>"
  regexDownloadsSingleFile = re("file=\"(?P<url>.+?)\">")
  regexDownloadsMultipleFiles = re("url: *\"(?P<url>.+?)\">")


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
      error [ "Synopsis: `{{ include fileName(.gd|.shader) [anchorName] }}`"
            , fmt"{result}: Incorrect include arguments. Expected 1 or 2 arguments. Skipping..."
            ].join(NL)
      return match.match

  proc replaceMarkdownCodeBlock(match: RegexMatch): string =
    let parts = match.captures.toTable()
    let language = parts.getOrDefault("language", "gdscript")
    result = "```" & language & "\n" & parts["body"].replace(regexShortcodeInclude, replaceIncludeShortcode) & "```"
    
  result = content.replace(regexMarkdownCodeBlock, replaceMarkdownCodeBlock)


proc makePathsAbsolute(content: string, fileName: string, pathPrefix = ""): string =
  ## Find image paths and download file paths and turns relative paths into absolute paths.
  ## pathPrefix is an optional prefix to preprend to the file path.

  proc makeUrlAbsolute(relativePath: string): string =
    ## Calculates and returns an absolute url for a relative file path.
    const META_MDFILE = "_index.md"

    var slug: seq[string]
    if fileName in cacheSlug:
      slug = cacheSlug[fileName]
    else:
      for directory in fileName.parentDirs(inclusive = false):
        if directory.endsWith("content"):
          break

        let meta_mdpath = directory / META_MDFILE
        if meta_mdpath.fileExists:
          for line in readFile(meta_mdpath).split("\n"):
            if line.startsWith("slug: "):
              slug.add(line.replace("slug: ", ""))
              break
        else:
          slug.add(directory.lastPathPart())
      slug = slug.reversed
      cacheSlug[fileName] = slug

    result = (@[pathPrefix] & slug & relativePath.split(AltSep)).join($AltSep)

  proc replaceMarkdownImagePaths(match: RegexMatch): string =
    let
      parts = match.captures.toTable()
      alt = parts.getOrDefault("alt", "")
      pathAbsolute = makeUrlAbsolute(parts["path"])

    result = fmt"![{alt}]({pathAbsolute})"

  proc replaceHtmlImagePaths(match: RegexMatch): string =
    let
      parts = match.captures.toTable()
      path = parts["path"]

    result = match.match.replace(path, makeUrlAbsolute(path))

  proc replaceDownloadPaths(match: RegexMatch): string =

    proc replaceDownloadPath(fileMatch: RegexMatch): string =
      let url = fileMatch.captures.toTable()["url"]
      result = fileMatch.match.replace(url, makeUrlAbsolute(url))

    result = match.match.replace(regexDownloadsSingleFile, replaceDownloadPath)
    result = result.replace(regexDownloadsMultipleFiles, replaceDownloadPath)

  result = content.replace(regexMarkdownImage, replaceMarkdownImagePaths)
  result = content.replace(regexHtmlImage, replaceHtmlImagePaths)
  result = result.replace(regexDownloads, replaceDownloadPaths)


proc addGodotIcons(content: string): string =
  proc replaceGodotIcon(match: RegexMatch): string =
    let className = match.captures.toTable()["class"]
    let cssClass = ["icon", className.strip(chars = {'`'}).replace(regexCapital, "_$#")].join().toLower()
    if cssClass in CACHE_GODOT_ICONS:
      result = "<Icon name=\"" & cssClass & "\"/>"
    else:
      info fmt"Couldn't find icon for `{cssClass}`. Skipping..."
      result = match.match

  result = content.replace(regexGodotBuiltIns, replaceGodotIcon)


proc processContent*(fileContent: string, fileName: string, pathPrefix = ""): string =
  const ROOT_SECTION_FOLDERS = @["courses", "bundles", "pages", "posts"]

  var prefix = pathPrefix
  if prefix == "":
    for folderName in ROOT_SECTION_FOLDERS:
      if folderName & AltSep in fileName:
        prefix = folderName
        break
    if prefix.isEmptyOrWhitespace():
      error fmt"The file {fileName} should be in one of the following folders: {ROOT_SECTION_FOLDERS}"

  result = fileContent.preprocessCodeListings().makePathsAbsolute(fileName, pathPrefix).addGodotIcons()
