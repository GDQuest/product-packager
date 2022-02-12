import std/
  [ algorithm
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


const
  GD_EXT* = ".gd"
  MD_EXT* = ".md"


var findFile*: string -> string

proc prepareFindFile*(dir: string, ignore: openArray[string] = []): string -> string =
  let (gitDir, exitCode) = execCmdEx("git rev-parse --show-toplevel", workingDir = dir)
  if exitCode != 0: ["[ERROR]", gitDir].join(SPACE).quit

  let
    cacheFiles = collect:
      for path in walkDirRec(gitDir.strip, relative = true):
        if ((path.endsWith(GD_EXT) or path.endsWith(MD_EXT)) and
            not ignore.any(x => path.isRelativeTo(x))
        ): path

    cache = collect(
      for k, v in cacheFiles.groupBy(extractFilename): (k, v)
    ).toTable

  return func(name: string): string =
    if not (name in cache or name in cacheFiles):
      let candidates = cacheFiles
        .mapIt((score: name.fuzzyMatchSmart(it), path: it))
        .sorted((x, y) => cmp(x.score, y.score), SortOrder.Descending)[0 .. min(5, cacheFiles.len)]
        .mapIt(it.path)

      raise newException(ValueError, (
        @[ fmt"`{name}` doesnt exist. Check your path/name."
         , "First 5 possible candidates:" ] & candidates).join(NL))

    elif name in cache and cache[name].len != 1:
      raise newException(ValueError, (
        @[ fmt"`{name}` is associated with multiple files:"] &
           cache[name] & @["Use a file path in your shortcode instead."]).join(NL))

    elif name in cache:
      return cache[name][0]

    else:
      return name
