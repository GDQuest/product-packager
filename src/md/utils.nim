import std/
  [ algorithm
  , logging
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


type Cache = tuple[ files: seq[string]
                  , table: Table[string, seq[string]]
                  , findFile: string -> string
                  ]


let logger* = newConsoleLogger(lvlWarn, useStderr = true)
addHandler(logger)


var cache*: Cache

proc prepareCache*(workingDir, courseDir: string; ignoreDirs: openArray[string]): Cache =
  let
    cacheFiles = block:
      let searchDirs = walkDir(workingDir, relative = true).toSeq
        .filterIt(it.kind == pcDir and not it.path.startsWith(".") and it.path notin ignoreDirs)
        .mapIt(it.path)

      var blockResult: seq[string]

      for path in searchDirs.mapIt(walkDirRec(workingDir / it).toSeq).concat:
        if (path.toLower.endsWith(GD_EXT) or path.toLower.endsWith(SHADER_EXT)):
          blockResult.add path

      for path in walkDirRec(workingDir / courseDir):
        if path.toLower.endsWith(MD_EXT):
          blockResult.add path

      blockResult

    cacheTable = collect(for k, v in cacheFiles.groupBy(extractFilename): (k, v)).toTable

  result.files = cacheFiles
  result.table = cacheTable
  result.findFile = func(name: string): string =
    if not (name in cacheTable or name in cacheFiles):
      let
        filteredCandidates = cacheFiles.filterIt(it.endsWith(name.splitFile.ext))
        candidates = filteredCandidates
          .mapIt((score: name.fuzzyMatchSmart(it), path: it))
          .sorted((x, y) => cmp(x.score, y.score), Descending)[0 .. min(5, filteredCandidates.len - 1)]
          .mapIt("\t" & it.path)

      raise newException(ValueError, (
        fmt"`{name}` doesn't exist. Possible candidates:" &
        candidates &
        "Skipping..."
      ).join(NL))

    elif name in cacheTable and cacheTable[name].len != 1:
      raise newException(ValueError, (
        fmt"`{name}` is associated with multiple files:" &
        cacheTable[name] &
        fmt"Relative to {workingDir}. Use a file path in your shortcode instead."
      ).join(NL))

    elif name in cacheTable:
      return cacheTable[name][0]

    else:
      return name
