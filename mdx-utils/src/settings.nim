## This module parses command line arguments, reads the configuration file,
## and converts that into an object that the build system can use for its execution settings.
import std/strformat
import std/strutils
import std/parseopt
import std/parsecfg
import std/os
import std/sequtils
import std/logging
import customlogger

type BuildSettings* = object
  ## This object represents the running configuration of the build system.
  ## The fields are filled with either default values or values found in `CFG_FILE`
  inputDir*: string

  ## The root folder of the project where the program is run. By default the program looks in the current working directory and parent directories for a configuration file or the content directory.
  projectDir*: string
  ## The directory where the source course content is stored.
  contentDir*: string
  ## Root directory for the output of the build system. By default, it's set to $projectDir/dist.
  distDir*: string

  ## (Optional) Directory path to output the processed content, relative to $distDir. By default, it's not set and the program outputs to $distDir directly.
  ## If you need to output to, for example, $distDir/app/courses/my-course, you can set this to "app/courses/my-course".
  outContentDir*: string

  ## List of directory paths relative to $inputDir where Godot projects are stored.
  ## Used to find code files to consider for the build.
  godotProjectDirs*: seq[string]
  ## List of directory paths relative to $inputDir to ignore in the build process.
  ## Note: Dot folders are automatically ignored. You only need to add other directories.
  ignoreDirs*: seq[string]
  ## If `true`, the program will delete the `distDir` before building the project.
  isCleaning*: bool
  ## If `true`, the program will reduce printed output to a minimum.
  isQuiet*: bool
  ## If `true`, the program will not write any files to disk and only output messages to the console.
  isDryRun*: bool
  ## If `true`, the program will print the list of media files included in the course.
  isShowingMedia*: bool
  ## Prefix to preprend to markdown image urls when making them absolute for GDSchool.
  imagePathPrefix*: string

func `$`*(appSettings: BuildSettings): string =
  result = "AppSettings:\n"
  for name, value in appSettings.fieldPairs:
    when value is seq:
      result.add("    " & name & ": " & value.join(", ") & "\n")
    else:
      result.add("    " & name & ": " & $value & "\n")

const
  COURSE_DIR = "content"
  DIST_DIR = "dist"
  GODOT_PROJECT_DIRS = @["godot-project"]
  CFG_FILE = "gdschool.cfg"
  HELP_MESSAGE =
    """
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
  --dry-run             print the list of files that would be processed without
                        actually processing them. This argument has no short form.
  -s, --show-media      print the list of media files included in the course.
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

proc resolveAppSettings(appSettings: BuildSettings): BuildSettings =
  ## Fills `BuildSettings` with either defaults or values found in `CFG_FILE`
  ## if it exists and there were no matching command line arguments given.
  ##
  ## Returns the updated `BuildSettings` object.
  ##
  ## *Note* that it also stops the execution if there was an error with
  ## the given values.
  result = appSettings
  # Tries to find the root directory of the course project by checking
  # either `CFG_FILE` or `appSettings.contentDir` exist.
  # If a valid course project was found it returns the updated
  # `BuildSettings.projectDir`.
  for dir in result.inputDir.parentDirs:
    if (dir / CFG_FILE).fileExists or (dir / result.contentDir).dirExists:
      result.projectDir = dir
      break

  if (result.projectDir / CFG_FILE).fileExists:
    let config = loadConfig(result.projectDir / CFG_FILE)
    if result.contentDir == "":
      result.contentDir = config.getSectionValue("", "contentDir", COURSE_DIR)

    if result.distDir == "":
      result.distDir = config.getSectionValue("", "distDir", DIST_DIR)

    if result.outContentDir == "":
      result.outContentDir = config.getSectionValue("", "outContentDir", "")

    if result.ignoreDirs.len() == 0:
      result.ignoreDirs =
        config.getSectionValue("", "ignoreDirs").split(",").mapIt(it.strip())

    if result.godotProjectDirs.len() == 0:
      let godotProjectDirs = config
        .getSectionValue("", "godotProjectDirs")
        .split(",")
        .mapIt(it.strip())
        .filterIt(not it.isEmptyOrWhitespace())

      if godotProjectDirs.len() > 0:
        result.godotProjectDirs = godotProjectDirs

  if result.contentDir == "":
    result.contentDir = COURSE_DIR
  if result.distDir == "":
    result.distDir = DIST_DIR

  if not result.isCleaning:
    if not dirExists(result.projectDir / result.contentDir):
      fmt"Can't find course directory `{result.projectDir / result.contentDir}`. Exiting.".quit

    let ignoreDirsErrors = result.ignoreDirs
      .filterIt(not dirExists(result.projectDir / it))
      .mapIt("\t{result.projectDir / it}".fmt)

    if ignoreDirsErrors.len != 0:
      echo(("Invalid ignore directories:" & ignoreDirsErrors).join("\n"))

    result.ignoreDirs.add result.distDir

proc getAppSettings*(): BuildSettings =
  result.inputDir = getCurrentDir().absolutePath
  result.projectDir = result.inputDir

  for kind, key, value in getopt(
    shortNoVal = {'h', 'v', 'q', 'd', 's'},
    longNoVal = @["clean", "help", "verbose", "quiet", "dry-run", "show-media"],
  ):
    case kind
    of cmdEnd:
      break
    of cmdArgument:
      if dirExists(key):
        result.inputDir = key.absolutePath
      else:
        quit fmt"Invalid input directory: `{key}`"
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        quit HELP_MESSAGE.fmt
      of "clean":
        result.isCleaning = true
      of "course-dir", "c":
        result.contentDir = value
      of "dist-dir", "d":
        result.distDir = value
      of "ignore-dir", "i":
        result.ignoreDirs.add value
      of "verbose", "v":
        logger.levelThreshold = logging.lvlAll
      of "quiet", "q":
        result.isQuiet = true
      of "dry-run":
        result.isDryRun = true
      of "show-media", "s":
        result.isShowingMedia = true
      else:
        quit fmt"Unrecognized command line option: `{key}`\n\nHelp:\n{HELP_MESSAGE.fmt}"

  result = result.resolveAppSettings()
