import std/[algorithm, os, sequtils, strformat, strutils, sugar, tables]
import fuzzy
import itertools
import ../settings

const
  GD_EXT* = ".gd"
  MD_EXT* = ".md"
  MDX_EXT* = ".mdx"
  SHADER_EXT* = ".gdshader"

type Cache* = ref object
  ## Read-only cache that stores all the paths to the Markdown, GDScript, and
  ## maps the code file names to their paths for easy lookup.
  ## Must be initialized with `prepareCache()` before use.
  isInitialized: bool
  codeFiles: seq[string]
  contentFiles: seq[string]
  codeFilenameToPath: Table[string, seq[string]]

var fileCache*: Cache = nil
  ## Global instance of the Cache object that has to be initialized with
  ## `prepareCache()`. This is a read-only cache that stores all the paths to
  ## the Markdown, GDScript, that's initialized once at the start of the build
  ## process.
  ## Keeping it read-only ensures consistency and also enables easy
  ## multithreading in the future without requiring locks.

proc prepareCache*(appSettings: BuildSettings): Cache =
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
  let subDirs = walkDir(appSettings.projectDir, relative = true)
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
        let fullPath = relativePath(godotProjectDir / path, appSettings.projectDir)
        codeFiles.add(fullPath)

  const CONTENT_FILE_EXTENSIONS = @[MD_EXT, MDX_EXT]
  for path in walkDirRec(appSettings.contentDir, relative = true):
    if "/." in path:
      continue
    let ext = path.splitFile().ext
    if ext in CONTENT_FILE_EXTENSIONS:
      let fullPath = relativePath(appSettings.contentDir / path, appSettings.projectDir)
      contentFiles.add(fullPath)

  result = new Cache
  result.codeFiles = codeFiles
  result.contentFiles = contentFiles
  result.codeFilenameToPath = collect(
    for k, v in codeFiles.groupBy((s) => extractFilename(s)):
      {k: v}
  )
  result.isInitialized = true

proc getContentFiles*(cache: Cache): lent seq[string] =
  assert cache.isInitialized, "Cache must be initialized before use"
  return cache.contentFiles

proc findCodeFile*(cache: Cache, name: string): string =
  assert cache.isInitialized, "Cache must be initialized before use"
  if not (name in cache.codeFilenameToPath or name in cache.codeFiles):
    let
      filteredCandidates =
        cache.codeFiles.filterIt(it.toLower.endsWith(name.splitFile.ext))
      candidates = filteredCandidates
      .mapIt((score: name.fuzzyMatchSmart(it), path: it))
      .sorted((x, y) => cmp(x.score, y.score), Descending)[
        0 .. min(5, filteredCandidates.len - 1)
      ].mapIt("\t" & it.path)

    raise newException(
      ValueError,
      (fmt"`{name}` doesn't exist. Possible candidates:" & candidates).join("\n"),
    )
  elif name in cache.codeFilenameToPath and cache.codeFilenameToPath[name].len != 1:
    raise newException(
      ValueError,
      (
        fmt"`{name}` is associated with multiple files:" & cache.codeFilenameToPath[
          name
        ] &
        fmt"Relative to the current working directory. Use a file path in your shortcode instead."
      ).join("\n"),
    )
  elif name in cache.codeFilenameToPath:
    return cache.codeFilenameToPath[name][0]
  else:
    return name
