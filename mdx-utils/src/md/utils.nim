# TODO: refactor to get rid of unnecessary imports
import std/[algorithm, os, sequtils, strformat, strutils, sugar, tables]
import fuzzy
import itertools
import ../settings

const
  SPACE* = " "
  GD_EXT* = ".gd"
  MD_EXT* = ".md"
  MDX_EXT* = ".mdx"
  SHADER_EXT* = ".gdshader"
  HTML_EXT* = ".html"

type
  Cache =
    tuple[
      codeFiles: seq[string],
      contentFiles: seq[string],
      table: Table[string, seq[string]],
      findCodeFile: string -> string,
    ]
  Report* = object
    built*: int
    errors*: int
    skipped*: int

# TODO: try to find a way to not start this as nil, to avoid errors when the cache is not initialized
# TODO: make this a ref object?
var cache*: Cache
  ## |
  ## Global cache that has to be initialized with `prepareCache()`.

proc `$`*(r: Report): string =
  fmt"Summary: {r.built} built, {r.errors} errors, {r.skipped} skipped."

proc prepareCache*(appSettings: AppSettingsBuildGDSchool): Cache =
  ## Returns a `Cache` object with:
  ##   - `return.files`: `seq[string]` stores all Markdown, GDScript and Shader
  ##                     paths.
  ##   - `return.table`: `Table[string, seq[string]]` with keys being the file
  ##                     base names and values being a sequence of paths.
  ##                     One key can have multiple paths associated with it in
  ##                     which case it isn't clear which to use with
  ##                     `< Link />` and `<Include ... />` shortcodes.
  ##   - `return.findFile`: `string -> string` is the function that searches for
  ##                        paths in both `return.files` and `return.table`.
  ##                        It raises a `ValueError` if:
  ##                          - the file name isn't stored in the cache.
  ##                          - the file name is associated with multiple paths.
  var
    codeFiles: seq[string]
    contentFiles: seq[string]
  let subDirs = walkDir(appSettings.workingDir, relative = true)
    .toSeq()
    .filterIt(
      it.kind == pcDir and not it.path.startsWith(".") and
        it.path notin appSettings.ignoreDirs
    )
    .mapIt(it.path)
  let godotDirs =
    if appSettings.godotProjectDirs.len() == 0:
      subDirs
    else:
      subDirs.filterIt(it in appSettings.godotProjectDirs)

  const CODE_FILE_EXTENSIONS = @[GD_EXT, SHADER_EXT]
  for godotProjectDir in godotDirs:
    for path in walkDirRec(godotProjectDir, relative = true):
      if "/." in path:
        continue
      let ext = path.splitFile().ext
      if ext in CODE_FILE_EXTENSIONS:
        let fullPath = relativePath(godotProjectDir / path, appSettings.workingDir)
        codeFiles.add(fullPath)

  const CONTENT_FILE_EXTENSIONS = @[MD_EXT, MDX_EXT]
  for path in walkDirRec(appSettings.contentDir, relative = true):
    if "/." in path:
      continue
    let ext = path.splitFile().ext
    if ext in CONTENT_FILE_EXTENSIONS:
      let fullPath = relativePath(appSettings.contentDir / path, appSettings.workingDir)
      contentFiles.add(fullPath)

  let cacheTable = collect(
    for k, v in codeFiles.groupBy((s) => extractFilename(s)):
      {k: v}
  )

  result.codeFiles = codeFiles
  result.contentFiles = contentFiles
  result.table = cacheTable
  result.findCodeFile =
    func (name: string): string =
      if not (name in cacheTable or name in codeFiles):
        let
          filteredCandidates =
            codeFiles.filterIt(it.toLower.endsWith(name.splitFile.ext))
          candidates = filteredCandidates
          .mapIt((score: name.fuzzyMatchSmart(it), path: it))
          .sorted((x, y) => cmp(x.score, y.score), Descending)[
            0 .. min(5, filteredCandidates.len - 1)
          ].mapIt("\t" & it.path)

        raise newException(
          ValueError,
          (fmt"`{name}` doesn't exist. Possible candidates:" & candidates).join("\n"),
        )
      elif name in cacheTable and cacheTable[name].len != 1:
        raise newException(
          ValueError,
          (
            fmt"`{name}` is associated with multiple files:" & cacheTable[name] &
            fmt"Relative to the current working directory. Use a file path in your shortcode instead."
          ).join("\n"),
        )
      elif name in cacheTable:
        return cacheTable[name][0]
      else:
        return name
