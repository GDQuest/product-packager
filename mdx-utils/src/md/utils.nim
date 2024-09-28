import std/[algorithm, os, sequtils, strformat, strutils, sugar, tables]
import fuzzy
import itertools

const
  SPACE* = " "
  NL* = "\n"
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

var cache*: Cache
  ## |
  ## Global cache that has to be initialized with `prepareCache()`.

proc `$`*(r: Report): string =
  fmt"Summary: {r.built} built, {r.errors} errors, {r.skipped} skipped."

proc prepareCache*(
    workingDir, contentDir: string, ignoreDirs: openArray[string]
): Cache =
  ## Retruns a `Cache` object with:
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
  let searchDirs = walkDir(workingDir, relative = true)
    .toSeq()
    .filterIt(
      it.kind == pcDir and not it.path.startsWith(".") and it.path notin ignoreDirs
    )
    .mapIt(it.path)

  for searchDir in searchDirs:
    for path in walkDirRec(workingDir / searchDir, relative = true).toSeq().concat():
      if "/." in path:
        continue
      if (path.toLower.endsWith(GD_EXT) or path.toLower.endsWith(SHADER_EXT)):
        codeFiles.add(searchDir / path)
      elif path.toLower.endsWith(MD_EXT) or path.toLower.endsWith(MDX_EXT):
        contentFiles.add(searchDir / path)

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
          (fmt"`{name}` doesn't exist. Possible candidates:" & candidates).join(NL),
        )
      elif name in cacheTable and cacheTable[name].len != 1:
        raise newException(
          ValueError,
          (
            fmt"`{name}` is associated with multiple files:" & cacheTable[name] &
            fmt"Relative to {workingDir}. Use a file path in your shortcode instead."
          ).join(NL),
        )
      elif name in cacheTable:
        return workingDir / cacheTable[name][0]
      else:
        return workingDir / name
