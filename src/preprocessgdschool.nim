import std/
  [ logging
  , os
  , parseopt
  , parsecfg
  , re
  , sequtils
  , strformat
  , strutils
  , terminal
  ]
import md/
  [ preprocessgdschool
  , utils
  ]
import customlogger, types


const
  META_MDFILE = "_index.md"
  COURSE_DIR = "content"
  DIST_DIR = "dist"
  GODOT_PROJECT_DIRS = @["godot-project"]
  CFG_FILE = "gdschool.cfg"
  HELP_MESSAGE = """
{getAppFilename().extractFilename} [options] [dir]

Build GDQuest-formatted Godot courses from Markdown.

[dir] is optional and can be a subdirectory of the course project. It defaults
to the current directory.

This app finds the project root directory based on --course-dir value or if it
finds {CFG_FILE}. Command line options take priority over {CFG_FILE}.

Options:
  -c, --course-dir:DIR  course project directory name.
                        Default: {COURSE_DIR}.
                        *Note* that DIR is relative to the course project
                        root directory.
  -d, --dist-dir:DIR    directory name for output.
                        Default: {DIST_DIR}.
                        *Note* that DIR is relative to the course project
                        root directory.
  -f, --force           run even if course files are older than
                        the existing output files.
                        Default: false.
  -g, --godot-project-dir:DIR
                        add DIR to a list for copying to {DIST_DIR}. All
                        anchor comments will be removed from the GDScript
                        source files.
                        *Note*
                          - That DIR is relative to the course project
                            root directory.
                        Default: {GODOT_PROJECT_DIRS}.
  -h, --help            print this help message.
      --clean           remove output directory.
                        Default: false.
  -i, --ignore-dir:DIR  add DIR to a list to ignore when caching Markdown,
                        GDScript and Shader files. This option can be
                        repeated multiple times. The app ignores dot folders.
                        This option adds directories on top of that.
                        *Note*
                          - That DIR is relative to the course project
                            root directory.
                          - The outut directory is automatically
                            added to the ignored list.
  -v, --verbose         print extra information when building the course.

Shortcodes:
  {{{{ include fileName(.gd|.shader) [anchorName] }}}}
    This shortcode is replaced by the contents of `fileName(.gd|.shader)`.

    If the `anchorName` optional argument is given, the contents within the named anchor
    is included instead of the whole file.

    Note that the anchor format for `.gd` files is:

    ```
    # ANCHOR: anchorName
    relevant content in fileName.gd
    # END: anchorName
    ```

    For `.shader` files replace # with //."""


let
  RegexSlug = re"slug: *"
  RegexDepends = re"{(?:%|{)\h*include\h*(\H+).*\h*(?:%|})}" ## |
  ## Extract the file name or path to calculate GDScript/Shader dependencies
  ## based on the `{{ include ... }}` shortcode.


proc getDepends(contents: string): seq[string] =
  ## Finds course files GDScript and Shader dependencies based on
  ## the `{{ include ... }}` shortcode.
  contents
    .findAll(RegexDepends)
    .mapIt(it.replacef(RegexDepends, "$1")).deduplicate
    .mapIt(
      try:
        cache.findFile(it)
      except ValueError:
        setForegroundColor(fgYellow)
        warn [ fmt"While looking for dependencies I got:"
             , getCurrentExceptionMsg()
             ].join(NL)
        setForegroundColor(fgDefault)
        ""
    ).filterIt(it != "")


proc resolveWorkingDir(appSettings: AppSettingsBuildGDSchool): AppSettingsBuildGDSchool =
  ## Tries to find the root directory of the course project by checking
  ## either `CFG_FILE` or `appSettings.courseDir` exist.
  ##
  ## If a valid course project was found it returns the updated
  ## `AppSettingsBuildGDSchool.workingDir`.
  result = appSettings
  for dir in appSettings.inputDir.parentDirs:
    if (dir / CFG_FILE).fileExists or (dir / result.courseDir).dirExists:
      result.workingDir = dir
      break


proc resolveAppSettings(appSettings: AppSettingsBuildGDSchool): AppSettingsBuildGDSchool =
  ## Fills `AppSettingsBuildGDSchool` with either defaults or values found in `CFG_FILE`
  ## if it exists and there were no matching command line arguments given.
  ##
  ## Returns the updated `AppSettingsBuildGDSchool` object.
  ##
  ## *Note* that it also stops the execution if there was an error with
  ## the given values.
  result = appSettings
  result = resolveWorkingDir(result)

  if (result.workingDir / CFG_FILE).fileExists:
    let cfg = loadConfig(result.workingDir / CFG_FILE)
    if result.courseDir == "": result.courseDir = cfg.getSectionValue("", "courseDir", COURSE_DIR)
    if result.distDir == "": result.distDir = cfg.getSectionValue("", "distDir", DIST_DIR)
    if result.godotProjectDirs.len == 0: result.godotProjectDirs = cfg.getSectionValue("", "godotProjectDirs").split(",").mapIt(it.strip)
    if result.ignoreDirs.len == 0: result.ignoreDirs = cfg.getSectionValue("", "ignoreDirs").split(",").mapIt(it.strip)

  if result.courseDir == "": result.courseDir = COURSE_DIR
  if result.godotProjectDirs.len == 0: result.godotProjectDirs = GODOT_PROJECT_DIRS
  if result.distDir == "": result.distDir = DIST_DIR

  if not result.isCleaning:
    if not dirExists(result.workingDir / result.courseDir):
      fmt"Can't find course directory `{result.workingDir / result.courseDir}`. Exiting.".quit

    let ignoreDirsErrors = result.ignoreDirs
      .filterIt(not dirExists(result.workingDir / it))
      .mapIt("\t{result.workingDir / it}".fmt)

    if ignoreDirsErrors.len != 0:
      warn ("Invalid ignore directories:" & ignoreDirsErrors).join(NL)

    result.ignoreDirs.add result.distDir


proc getAppSettings(): AppSettingsBuildGDSchool =
  ## Returns an `AppSettingsBuildGDSchool` object with appropriate values. It stops the
  ## execution if invalid values were found.
  result.inputDir = ".".absolutePath
  result.workingDir = result.inputDir

  for kind, key, value in getopt(
    shortNoVal = {'f', 'h', 'v'},
    longNoVal = @["clean", "force", "help", "verbose"]
  ):
    case kind
    of cmdEnd: break

    of cmdArgument:
      if dirExists(key): result.inputDir = key.absolutePath
      else: fmt"Invalid input directory: `{key}`".quit

    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": HELP_MESSAGE.fmt.quit(QuitSuccess)
      of "clean", "": result.isCleaning = true
      of "course-dir", "c": result.courseDir = value
      of "dist-dir", "d": result.distDir = value
      of "force", "f": result.isForced = true
      of "godot-project-dir", "g": result.godotProjectDirs.add value
      of "ignore-dir", "i": result.ignoreDirs.add value
      of "verbose", "v": logger.levelThreshold = lvlAll
      else: [ fmt"Unrecognized command line option: `{key}`."
            , ""
            , "Help:"
            , HELP_MESSAGE.fmt
            , "Exiting."
            ].join(NL).quit

  result = result.resolveAppSettings


proc process(appSettings: AppSettingsBuildGDSchool) =
  # Copy asset/all subfolders
  createDir(appSettings.distDir)
  for dirIn in walkDirs(appSettings.workingDir / appSettings.courseDir / "**" / "*"):
    let dirOut = dirIn.replace(appSettings.courseDir & DirSep, appSettings.distDir & DirSep)
    copyDir(dirIn, dirOut)
  
  cache = prepareCache(appSettings.workingDir, appSettings.courseDir, appSettings.ignoreDirs)
  for fileIn in cache.files.filterIt(
    it.toLower.endsWith(MD_EXT) and
    (appSettings.courseDir & DirSep) in it
  ):
    let
      fileIn = appSettings.workingDir / fileIn
      fileOut = fileIn.replace(appSettings.courseDir & DirSep, appSettings.distDir & DirSep)
    
    var processingMsg = fmt"Processing `{fileIn.relativePath(appSettings.workingDir)}` -> `{fileOut.relativePath(appSettings.workingDir)}`..."
    if logger.levelThreshold == lvlAll:
      info processingMsg
    else:
      echo processingMsg

    let
      fileInContents = readFile(fileIn)
      doProcess = (
        appSettings.isForced or
        not fileExists(fileOut) or
        fileIn.fileNewer(fileOut) or
        fileInContents.getDepends.anyIt(it.fileNewer(fileOut))
      )

    if doProcess:
      createDir(fileOut.parentDir)
      info fmt"Creating output `{fileOut.parentDir}` directory..."

      if fileIn.endsWith(META_MDFILE):
        copyFile(fileIn, fileOut)
      else:
        writeFile(fileOut, preprocess(fileIn, fileInContents))

    else:
      info processingMsg


when isMainModule:
  let appSettings = getAppSettings()

  if appSettings.isCleaning:
    removeDir(appSettings.workingDir / appSettings.distDir)
    fmt"Removing `{appSettings.workingDir / appSettings.distDir}`. Exiting.".quit(QuitSuccess)

  echo appSettings
  process(appSettings)
  stdout.resetAttributes()

