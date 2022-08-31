import std/
  [ algorithm
  , os
  , sequtils
  , strformat
  , strutils
  , sugar
  , tables
  ]
import fuzzy
import itertools


const
  SPACE* = " "
  NL* = "\n"
  GD_EXT* = ".gd"
  MD_EXT* = ".md"
  SHADER_EXT* = ".shader"
  HTML_EXT* = ".html"


type
  Cache = tuple[ files: seq[string]
               , table: Table[string, seq[string]]
               , findFile: string -> string
               ]
  Report* = object
    built*: int
    errors*: int
    skipped*: int


var cache*: Cache ## |
  ## Global cache that has to be initialized with `prepareCache()`.


proc `$`*(r: Report): string = fmt"Summary: {r.built} built, {r.errors} errors, {r.skipped} skipped."


proc prepareCache*(workingDir, courseDir: string; ignoreDirs: openArray[string]): Cache =
  ## Retruns a `Cache` object with:
  ##   - `return.files`: `seq[string]` stores all Markdown, GDScript and Shader
  ##                     paths.
  ##   - `return.table`: `Table[string, seq[string]]` with keys being the file
  ##                     base names and values being a sequence of paths.
  ##                     One key can have multiple paths associated with it in
  ##                     which case it isn't clear which to use with
  ##                     `{{ link ... }}` and `{{ include ... }}` shortcodes.
  ##   - `return.findFile`: `string -> string` is the function that searches for
  ##                        paths in both `return.files` and `return.table`.
  ##                        It raises a `ValueError` if:
  ##                          - the file name isn't stored in the cache.
  ##                          - the file name is associated with multiple paths.
  let
    cacheFiles = block:
      let searchDirs = walkDir(workingDir, relative = true).toSeq
        .filterIt(
          it.kind == pcDir and not it.path.startsWith(".") and
          it.path notin ignoreDirs
        ).mapIt(it.path)

      var blockResult: seq[string]

      for searchDir in searchDirs:
        for path in walkDirRec(workingDir / searchDir, relative = true).toSeq.concat:
          if (path.toLower.endsWith(GD_EXT) or path.toLower.endsWith(SHADER_EXT)):
            blockResult.add searchDir / path

      for path in walkDirRec(workingDir / courseDir, relative = true):
        if path.toLower.endsWith(MD_EXT):
          blockResult.add courseDir / path

      blockResult

    cacheTable = collect(for k, v in cacheFiles.groupBy((s) => extractFilename(s)): {k: v})

  result.files = cacheFiles
  result.table = cacheTable
  result.findFile = func(name: string): string =
    if not (name in cacheTable or name in cacheFiles):
      let
        filteredCandidates = cacheFiles.filterIt(it.toLower.endsWith(name.splitFile.ext))
        candidates = filteredCandidates
          .mapIt((score: name.fuzzyMatchSmart(it), path: it))
          .sorted((x, y) => cmp(x.score, y.score), Descending)[0 .. min(5, filteredCandidates.len - 1)]
          .mapIt("\t" & it.path)

      raise newException(ValueError, (fmt"`{name}` doesn't exist. Possible candidates:" & candidates).join(NL))

    elif name in cacheTable and cacheTable[name].len != 1:
      raise newException(ValueError, (
        fmt"`{name}` is associated with multiple files:" &
        cacheTable[name] &
        fmt"Relative to {workingDir}. Use a file path in your shortcode instead."
      ).join(NL))

    elif name in cacheTable:
      return workingDir / cacheTable[name][0]

    else:
      return workingDir / name
