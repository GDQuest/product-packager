import std/
  [ os
  , parseopt
  , parsecfg
  , sequtils
  , strformat
  , strutils
  ]
import md/
  [ assets
  , parser
  , preprocess
  , utils
  ]


type AppSettings = object
  inputDir: string
  workingDir: string
  courseDir: string
  distDir: string
  isCleaning: bool
  ignoreDirs: seq[string]


const
  COURSE_DIR = "content"
  DIST_DIR = "dist"
  CFG_FILE = "course.cfg"
  HELP_MESSAGE = """
HelpMessage"""


proc resolveAppSettings(appSettings: AppSettings): AppSettings =
  result = appSettings

  for dir in appSettings.inputDir.parentDirs:
    if (dir / CFG_FILE).fileExists:
      let cfg = loadConfig(dir / CFG_FILE)
      result.workingDir = dir

      if result.courseDir == "":
        result.courseDir = cfg.getSectionValue("", "courseDir", COURSE_DIR)

      if result.distDir == "":
        result.distDir = cfg.getSectionValue("", "distDir", DIST_DIR)

      if result.ignoreDirs.len == 0:
        result.ignoreDirs = cfg.getSectionValue("", "ignoreDirs").split(",").mapIt(it.strip)

    elif (dir / COURSE_DIR).dirExists:
      result.workingDir = dir

      if result.courseDir == "":
        result.courseDir = COURSE_DIR

      if result.distDir == "":
        result.distDir = DIST_DIR

  if not dirExists(result.workingDir / result.courseDir):
    fmt"Can't find course directory: `{result.workingDir / result.courseDir}`. Exiting...".quit

  let ignoreDirsErrors = result.ignoreDirs
    .filterIt(not dirExists(result.workingDir / it))
    .mapIt(fmt"Invalid ignore directory: `{result.workingDir / it}`.")
    .join(NL)

  if ignoreDirsErrors != "":
    [ignoreDirsErrors, "Exiting..."].join(SPACE).quit


proc getAppSettings(): AppSettings =
  result.inputDir = "."

  for kind, key, value in getopt(shortNoVal = {'h'}, longNoVal = @["clean", "help"]):
    case kind
    of cmdEnd: break

    of cmdArgument:
      if dirExists(key): result.inputDir = key
      else: fmt"Invalid input directory: `{key}`".quit

    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": HELP_MESSAGE.quit(QuitSuccess)
      of "clean", "": result.isCleaning = true
      of "course-dir", "c": result.courseDir = value
      of "dist-dir", "d": result.distDir = value
      of "ignore-dir", "i": result.ignoreDirs.add value

  result = result.resolveAppSettings


when isMainModule:
  let appSettings = getAppSettings()

  if appSettings.isCleaning:
    removeDir(appSettings.workingDir / appSettings.distDir)
    fmt"Removing `{appSettings.workingDir / appSettings.distDir}`. Exiting...".quit(QuitSuccess)

  else:
    cache = prepareCache(appSettings.workingDir, appSettings.courseDir, appSettings.ignoreDirs)
    echo cache.files.join(NL)
