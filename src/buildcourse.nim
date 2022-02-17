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
  isForced: bool

func `$`(appSettings: AppSettings): string =
  [ "AppSettings:"
  , "\tinputDir: {appSettings.inputDir}".fmt
  , "\tworkingDir: {appSettings.workingDir}".fmt
  , "\tcourseDir: {appSettings.courseDir}".fmt
  , "\tdistDir: {appSettings.distDir}".fmt
  , "\tignoreDirs: {appSettings.ignoreDirs.join(\", \")}".fmt
  , "\tpandocExe: {appSettings.pandocExe}".fmt
  , "\tpandocAssetsDir: {appSettings.pandocAssetsDir}".fmt
  , "\tisCleaning: {appSettings.isCleaning}".fmt
  , "\tisForced: {appSettings.isForced}".fmt
  ].join(NL)


const
  RAND_LEN = 8
  COURSE_DIR = "content"
  DIST_DIR = "dist"
  PANDOC_EXE = "pandoc"
  CFG_FILE = "course.cfg"
  HELP_MESSAGE = """
{getAppFilename().extractFilename} [options] [dir]

Build Godot courses from Markdown files using Pandoc.

[dir] is optional and can be a subdirectory of the course project. It defaults
to the current directory.

This app finds the project root directory based on --course-dir value or if it
finds {CFG_FILE}. Command line options take priority over {CFG_FILE}.

Options:
  -a, --pandoc-assets-dir:DIR
                        search for required Pandoc asset files in DIR:
                          - {CACHE_COURSE_CSS_NAME}
                          - {CACHE_GDSCRIPT_DEF_NAME}
                          - {CACHE_GDSCRIPT_THEME_NAME}
                        Default: internal assets specific to GDQuest.
  -c, --course-dir:DIR  course project directory name.
                        Default: {COURSE_DIR}.
  -d, --dist-dir:DIR    directory name for Pandoc output.
                        Default: {DIST_DIR}.
  -f, --force           run Pandoc even if course files are older than
                        the existing output files.
                        Default: false.
  -h, --help            this help message.
      --clean           remove Pandoc output directory.
                        Default: false.
  -i, --ignore-dir:DIR  add DIR to a list to ignore when caching Markdown,
                        GDScript and Shader files. This option can be
                        repeated multiple times. The app ignores dot folders.
                        This option adds directories on top of that.
  -p, --pandoc-exe:PATH Pandoc executable path or name.
  -v, --verbose         print extra information."""


proc getTempDir(workingDir: string): string = workingDir / [".tmp-", urandom(RAND_LEN).join[0 ..< RAND_LEN]].join

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
      fmt"Can't find `{result.pandocExe}` on your system. Exiting.".quit

    if not dirExists(result.workingDir / result.courseDir):
      fmt"Can't find course directory `{result.workingDir / result.courseDir}`. Exiting.".quit

    let ignoreDirsErrors = result.ignoreDirs
      .filterIt(not dirExists(result.workingDir / it))
      .mapIt(fmt"Invalid ignore directory: `{result.workingDir / it}`.")
      .join(NL)

    if ignoreDirsErrors != "":
      [fmt"{ignoreDirsErrors}", "Exiting."].join(NL).quit


proc getAppSettings(): AppSettings =
  result.inputDir = "."
  result.workingDir = result.inputDir

  for kind, key, value in getopt(shortNoVal = {'f', 'h', 'v'}, longNoVal = @["clean", "force", "help", "verbose"]):
    case kind
    of cmdEnd: break

    of cmdArgument:
      if dirExists(key): result.inputDir = key
      else: fmt"Invalid input directory: `{key}`".quit

    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": HELP_MESSAGE.fmt.quit(QuitSuccess)
      of "clean", "": result.isCleaning = true
      of "course-dir", "c": result.courseDir = value
      of "dist-dir", "d": result.distDir = value
      of "force", "f": result.isForced = true
      of "ignore-dir", "i": result.ignoreDirs.add value
      of "pandoc-exe", "p": result.pandocExe = value
      of "pandoc-assets-dir", "a": result.pandocAssetsDir = value 
      of "verbose", "v": logger.levelThreshold = lvlAll
      else: fmt"Unrecognized command line option: `{key}`. Exiting".quit

  result = result.resolveAppSettings


when isMainModule:
  let appSettings = getAppSettings()
  info appSettings

  if appSettings.isCleaning:
    removeDir(appSettings.workingDir / appSettings.distDir)
    fmt"Removing `{appSettings.workingDir / appSettings.distDir}`. Exiting.".quit(QuitSuccess)

  else:
    let
      tmpDir = getTempDir(appSettings.workingDir)
      courseCssFile = tmpDir / CACHE_COURSE_CSS_NAME
      gdscriptDefFile = tmpDir / CACHE_GDSCRIPT_DEF_NAME
      gdscriptThemeFile = tmpDir / CACHE_GDSCRIPT_THEME_NAME

    createDir(tmpDir)
    defer: removeDir(tmpDir)
    info fmt"Creating temporary directory `{tmpDir}`..."

    writeFile(courseCssFile, CACHE_COURSE_CSS)
    writeFile(gdscriptDefFile, CACHE_GDSCRIPT_DEF)
    writeFile(gdscriptThemeFile, CACHE_GDSCRIPT_THEME)

    let pandocAssetsCmdOptions = if appSettings.pandocAssetsDir == "": [ fmt"--css={courseCssFile}"
                                                                       , fmt"--syntax-definition={gdscriptDefFile}"
                                                                       , fmt"--highlight-style={gdscriptThemeFile}"
                                                                       ].join(SPACE)
                                 else: [ fmt"--css={appSettings.pandocAssetsDir / CACHE_COURSE_CSS_NAME}"
                                       , fmt"--syntax-definition=(appSettings.pandocAssetsDir / CACHE_GDSCRIPT_DEF_NAME)"
                                       , fmt"--highlight-style={appSettings.pandocAssetsDir / CACHE_GDSCRIPT_THEME_NAME}"
                                       ].join(SPACE)

    cache = prepareCache(appSettings.workingDir, appSettings.courseDir, appSettings.ignoreDirs)
    for fileIn in cache.files.filterIt(it.toLower.endsWith(MD_EXT)):
      let fileOut = fileIn.multiReplace((appSettings.courseDir & DirSep, appSettings.distDir & DirSep), (MD_EXT, HTML_EXT))
      info ["Processing:", "\t`{fileIn}` -> `{fileOut}`...".fmt].join(NL)

      if fileIn.fileNewer(fileOut) or appSettings.isForced:
        createDir(fileOut.parentDir)
        info fmt"Creating output `{fileOut.parentDir}` directory..."

        let cmd = [ appSettings.pandocExe
                  , "--self-contained"
                  , fmt"--resource-path={fileIn.parentDir}"
                  , fmt"--metadata=title:{fileOut.splitFile.name}"
                  , fmt"--output={fileOut}"
                  , pandocAssetsCmdOptions
                  , "-"
                  ].join(SPACE)
        info fmt"Executing: `{cmd}`..."

        let (output, exitCode) = execCmdEx(cmd, input = preprocess(fileIn))
        if exitCode != QuitSuccess:
          error fmt"{fileIn}:{output.strip}. Skipping..."

      else:
        info fmt"{fileIn} is older than {fileOut}. Skipping..."
