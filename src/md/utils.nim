import std/
  [ algorithm
  , logging
  , os
  , osproc
  , sequtils
  , strformat
  , strutils
  , sugar
  , tables
  ]
import fuzzy
import itertools
import parser


let errorLogger = newConsoleLogger(lvlWarn, useStderr = true)
addHandler(errorLogger)


const
  GD_EXT* = ".gd"
  MD_EXT* = ".md"


var findFile*: string -> string

proc prepareFindFile*(dir: string, ignore: openArray[string] = []): string -> string =
  var (rootDir, exitCode) = execCmdEx("git rev-parse --show-toplevel", workingDir = dir)
  if exitCode != QuitSuccess: rootDir.quit
  rootDir = rootDir.strip

  let
    cacheFiles = collect:
      for path in walkDirRec(rootDir, relative = true):
        if ((path.endsWith(GD_EXT) or path.endsWith(MD_EXT)) and
            not ignore.any(x => path.isRelativeTo(x))
        ): path

    cache = collect(
      for k, v in cacheFiles.groupBy(extractFilename): (k, v)
    ).toTable

  return func(name: string): string =
    if not (name in cache or name in cacheFiles):
      let candidates = cacheFiles
        .filterIt(it.endsWith(name.splitFile.ext))
        .mapIt((score: name.fuzzyMatchSmart(it), path: it))
        .sorted((x, y) => cmp(x.score, y.score), Descending)[0 .. min(5, cacheFiles.len)]
        .mapIt("\t" & it.path)

      raise newException(ValueError, (
        fmt"`{name}` doesnt exist. Possible candidates:" &
        candidates &
        fmt"Relative to {rootDir}. Skipping..."
      ).join(NL))

    elif name in cache and cache[name].len != 1:
      raise newException(ValueError, (
        fmt"`{name}` is associated with multiple files:" &
        cache[name] &
        fmt"Relative to {rootDir}. Use a file path in your shortcode instead."
      ).join(NL))

    elif name in cache:
      return joinPath(rootDir, cache[name][0])

    else:
      return joinPath(rootDir, name)
