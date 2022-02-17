import std/
  [ logging
  , os
  , osproc
  , parseopt
  , parsecfg
  , sequtils
  , strformat
  , strutils
  , sysrand
  ]
import md/
  [ preprocess
  , utils
  ]
import assets


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
  RAND_LEN = 8
  COURSE_DIR = "content"
  DIST_DIR = "dist"
  PANDOC_EXE = "pandoc"
  CFG_FILE = "course.cfg"
  HELP_MESSAGE = """
HelpMessage"""


proc genTempDir(): string = [".tmp-", urandom(RAND_LEN).join[0 ..< RAND_LEN]].join

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
    let
      tmpDir = appSettings.workingDir / genTempDir()
      courseCssFile = tmpDir / CACHE_COURSE_CSS_NAME
      gdscriptDefFile = tmpDir / CACHE_GDSCRIPT_DEF_NAME
      gdscriptThemeFile = tmpDir / CACHE_GDSCRIPT_THEME_NAME

    createDir(tmpDir)
    defer: removeDir(tmpDir)

    writeFile(courseCssFile, CACHE_COURSE_CSS)
    writeFile(gdscriptDefFile, CACHE_GDSCRIPT_DEF)
    writeFile(gdscriptThemeFile, CACHE_GDSCRIPT_THEME)

    let pandocAssetsCmdOptions = if appSettings.pandocAssetsDir == "": [ fmt"--css={courseCssFile}"
                                                                       , fmt"--syntax-definition={gdscriptDefFile}"
                                                                       , fmt"--highlight-style={gdscriptThemeFile}"
                                                                       ].join(SPACE)
                                 else: [ "--css=" & (appSettings.pandocAssetsDir / "course.css")
                                       , "--syntax-definition=" & (appSettings.pandocAssetsDir / "gdscript.xml")
                                       , "--highlight-style=" & (appSettings.pandocAssetsDir / "gdscript.theme")
                                       ].join(SPACE)

    cache = prepareCache(appSettings.workingDir, appSettings.courseDir, appSettings.ignoreDirs)
    for fileIn in cache.files.filterIt(it.toLower.endsWith(MD_EXT)):
      let fileOut = fileIn.multiReplace((appSettings.courseDir & DirSep, appSettings.distDir & DirSep), (MD_EXT, HTML_EXT))
      createDir(fileOut.parentDir)

      let (output, exitCode) = execCmdEx([ appSettings.pandocExe
                                         , "--self-contained"
                                         , fmt"--resource-path={fileIn.parentDir}"
                                         , fmt"--metadata=title:{fileOut.splitFile.name}"
                                         , fmt"--output={fileOut}"
                                         , pandocAssetsCmdOptions
                                         , "-"
                                         ].join(SPACE), input = preprocess(fileIn))

      if exitCode != QuitSuccess:
        error fmt"{fileIn}:{output.strip}. Skipping..."
