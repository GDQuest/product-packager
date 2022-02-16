import std/
  [ os
  , osproc
  , parseopt
  , parsecfg
  , sequtils
  , strformat
  , strutils
  ]
import md/
  [ preprocess
  , utils
  ]


type AppSettings = object
  inputDir: string
  workingDir: string
  courseDir: string
  distDir: string
  ignoreDirs: seq[string]
  pandocExe: string
  pandocAssetsDir: string
  isCleaning: bool


const
  COURSE_DIR = "content"
  DIST_DIR = "dist"
  PANDOC_EXE = "pandoc"
  CFG_FILE = "course.cfg"
  HELP_MESSAGE = """
HelpMessage"""


proc resolveWorkingDir(appSettings: AppSettings): AppSettings =
  result = appSettings
  for dir in appSettings.inputDir.parentDirs:
    if (dir / CFG_FILE).fileExists or (dir / COURSE_DIR).dirExists:
      result.workingDir = dir
      break


proc resolveAppSettings(appSettings: AppSettings): AppSettings =
  result = appSettings.resolveWorkingDir
  if result.courseDir == "": result.courseDir = COURSE_DIR
  if result.distDir == "": result.distDir = DIST_DIR
  if result.pandocExe == "": result.pandocExe = PANDOC_EXE

  if (result.workingDir / CFG_FILE).fileExists:
    let cfg = loadConfig(result.workingDir / CFG_FILE)
    if result.courseDir == "": result.courseDir = cfg.getSectionValue("", "courseDir", COURSE_DIR)
    if result.distDir == "": result.distDir = cfg.getSectionValue("", "distDir", DIST_DIR)
    if result.ignoreDirs.len == 0: result.ignoreDirs = cfg.getSectionValue("", "ignoreDirs").split(",").mapIt(it.strip)
    if result.pandocExe == "": result.pandocExe = cfg.getSectionValue("", "pandocExe", PANDOC_EXE)
    if result.pandocAssetsDir == "": result.pandocAssetsDir = cfg.getSectionValue("", "pandocAssetsDir")

  if not result.isCleaning:
    if findExe(result.pandocExe) == "":
      fmt"Can't find `{result.pandocExe}` on your system. Exiting...".quit

    if not dirExists(result.workingDir / result.courseDir):
      fmt"Can't find course directory: `{result.workingDir / result.courseDir}`. Exiting...".quit

    if not dirExists(result.pandocAssetsDir):
      fmt"Invalid Pandoc assets directory: `{result.pandocAssetsDir}`. Exiting...".quit

    let ignoreDirsErrors = result.ignoreDirs
      .filterIt(not dirExists(result.workingDir / it))
      .mapIt(fmt"Invalid ignore directory: `{result.workingDir / it}`.")
      .join(NL)

    if ignoreDirsErrors != "":
      [ignoreDirsErrors, "Exiting..."].join(SPACE).quit


proc getAppSettings(): AppSettings =
  result.inputDir = "."
  result.workingDir = result.inputDir

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
      of "pandoc-exe", "p": result.pandocExe = value
      of "pandoc-assets-dir": result.pandocAssetsDir = value 

  result = result.resolveAppSettings


when isMainModule:
  let appSettings = getAppSettings()

  if appSettings.isCleaning:
    removeDir(appSettings.workingDir / appSettings.distDir)
    fmt"Removing `{appSettings.workingDir / appSettings.distDir}`. Exiting...".quit(QuitSuccess)

  else:
    cache = prepareCache(appSettings.workingDir, appSettings.courseDir, appSettings.ignoreDirs)
    for fileIn in cache.files.filterIt(it.toLower.endsWith(MD_EXT)):
      let fileOut = fileIn.multiReplace((appSettings.courseDir & DirSep, appSettings.distDir & DirSep), (MD_EXT, HTML_EXT))
      fileOut.parentDir.createDir

      let (output, exitCode) = execCmdEx([ fmt"{appSettings.pandocExe}"
                                         , "--self-contained"
                                         , if appSettings.pandocAssetsDir != "": [ "--css=" & (appSettings.pandocAssetsDir / "course.css")
                                                                                 , "--syntax-definition=" & (appSettings.pandocAssetsDir / "gdscript.xml")
                                                                                 , "--highlight-style=" & (appSettings.pandocAssetsDir / "gdscript.theme")
                                                                                 ].join(SPACE) else: ""
                                         , fmt"--resource-path={fileIn.parentDir}"
                                         , fmt"--metadata=title:{fileOut.splitFile.name}"
                                         , fmt"--output={fileOut}"
                                         , "-"
                                         ].filterIt(it != "").join(SPACE), input = fileIn.preprocess)

      if exitCode != QuitSuccess:
        output.quit(exitCode)
