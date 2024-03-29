## Program to preprocess mdx files for GDQuest courses on GDSchool.
## Replaces include shortcodes with the contents of the included source code files.
## It also inserts components representing Godot icons in front of Godot class names.
import std/
  [ logging
  , os
  , parseopt
  , parsecfg
  , sequtils
  , strformat
  , strutils
  , terminal
  ]
import md/
  [ gdschool_preprocessor
  , utils
  ]
import customlogger, types


const
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
  -q, --quiet           suppress output

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


proc resolveWorkingDir(appSettings: AppSettingsBuildGDSchool): AppSettingsBuildGDSchool =
  ## Tries to find the root directory of the course project by checking
  ## either `CFG_FILE` or `appSettings.contentDir` exist.
  ##
  ## If a valid course project was found it returns the updated
  ## `AppSettingsBuildGDSchool.workingDir`.
  result = appSettings
  for dir in appSettings.inputDir.parentDirs:
    if (dir / CFG_FILE).fileExists or (dir / result.contentDir).dirExists:
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
    let config = loadConfig(result.workingDir / CFG_FILE)
    if result.contentDir == "": result.contentDir = config.getSectionValue("", "contentDir", COURSE_DIR)
    if result.distDir == "": result.distDir = config.getSectionValue("", "distDir", DIST_DIR)
    if result.ignoreDirs.len == 0: result.ignoreDirs = config.getSectionValue("", "ignoreDirs").split(",").mapIt(it.strip)

  if result.contentDir == "": result.contentDir = COURSE_DIR
  if result.distDir == "": result.distDir = DIST_DIR

  if not result.isCleaning:
    if not dirExists(result.workingDir / result.contentDir):
      fmt"Can't find course directory `{result.workingDir / result.contentDir}`. Exiting.".quit

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
    shortNoVal = {'h', 'v', 'q'},
    longNoVal = @["clean", "help", "verbose", "quiet"]
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
      of "course-dir", "c": result.contentDir = value
      of "dist-dir", "d": result.distDir = value
      of "ignore-dir", "i": result.ignoreDirs.add value
      of "verbose", "v": logger.levelThreshold = lvlAll
      of "quiet", "q": result.isQuiet = true
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
  for dirIn in walkDirs(appSettings.workingDir / appSettings.contentDir / "**"):
    let dirOut = dirIn.replace(appSettings.contentDir & DirSep, appSettings.distDir & DirSep)
    copyDir(dirIn, dirOut)
  
  cache = prepareCache(appSettings.workingDir, appSettings.contentDir, appSettings.ignoreDirs)
  for fileIn in cache.files.filterIt(
    (it.toLower.endsWith(MDX_EXT) or it.toLower.endsWith(MD_EXT)) and
    (appSettings.contentDir & DirSep) in it
  ):
    let
      fileIn = appSettings.workingDir / fileIn
      fileOut = fileIn.replace(appSettings.contentDir & DirSep, appSettings.distDir & DirSep)

    if not appSettings.isQuiet:
      let processingMsg = fmt"Processing `{fileIn.relativePath(appSettings.workingDir)}` -> `{fileOut.relativePath(appSettings.workingDir)}`..."
      if logger.levelThreshold == lvlAll:
        info processingMsg
      else:
        echo processingMsg

    let fileInContents = readFile(fileIn)
    createDir(fileOut.parentDir)
    if not appSettings.isQuiet:
      info fmt"Creating output `{fileOut.parentDir}` directory..."

    writeFile(fileOut, processContent(fileInContents))


when isMainModule:
  let appSettings = getAppSettings()

  if appSettings.isCleaning:
    removeDir(appSettings.workingDir / appSettings.distDir)
    fmt"Removing `{appSettings.workingDir / appSettings.distDir}`. Exiting.".quit(QuitSuccess)

  echo appSettings
  process(appSettings)
  stdout.resetAttributes()

