## Program to preprocess mdx files for GDQuest courses on GDSchool.
## Replaces include shortcodes with the contents of the included source code files.
## It also inserts components representing Godot icons in front of Godot class names.
import
  std/[
    logging, os, parseopt, parsecfg, sequtils, strformat, strutils, terminal, nre,
    tables,
  ]
import md/[gdschool_preprocessor, utils]
import customlogger, types

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

proc resolveWorkingDir(
    appSettings: AppSettingsBuildGDSchool
): AppSettingsBuildGDSchool =
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

proc resolveAppSettings(
    appSettings: AppSettingsBuildGDSchool
): AppSettingsBuildGDSchool =
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
    if result.contentDir == "":
      result.contentDir = config.getSectionValue("", "contentDir", COURSE_DIR)
    if result.distDir == "":
      result.distDir = config.getSectionValue("", "distDir", DIST_DIR)
    if result.ignoreDirs.len == 0:
      result.ignoreDirs =
        config.getSectionValue("", "ignoreDirs").split(",").mapIt(it.strip())

  if result.contentDir == "":
    result.contentDir = COURSE_DIR
  if result.distDir == "":
    result.distDir = DIST_DIR

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
  result.inputDir = getCurrentDir().absolutePath
  result.workingDir = result.inputDir

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
        logger.levelThreshold = lvlAll
      of "quiet", "q":
        result.isQuiet = true
      of "dry-run":
        result.isDryRun = true
      of "show-media", "s":
        result.isShowingMedia = true
      else:
        quit fmt"Unrecognized command line option: `{key}`\n\nHelp:\n{HELP_MESSAGE.fmt}"

  result = result.resolveAppSettings()

proc process(appSettings: AppSettingsBuildGDSchool) =
  # This cache lists code files (.gd, .gdshader) in the content directory and maps associated files.
  cache =
    prepareCache(appSettings.workingDir, appSettings.contentDir, appSettings.ignoreDirs)

  # Copy all files in the content directory to the dist directory recursively.
  #createDir(appSettings.distDir)
  #for dirIn in walkDirs(appSettings.workingDir / appSettings.contentDir / "**"):
  #  let dirOut = dirIn.replace(appSettings.contentDir & DirSep, appSettings.distDir & DirSep)
  #  copyDir(dirIn, dirOut)

  # TO DO:
  # - We process all MDX and MD files in the content directory.
  # - Parsing the markdown files should return a list of input media files that need to be copied.
  # - We build a list of output file paths for the media files.

  let
    regexImage = re"!\[.*\]\((?P<src>.+?)\)"
    regexVideoFile = re("<VideoFile.*src=[\"'](?P<src>[^\"']+?)[\"']")
  # File paths collected from input md and mdx files, with the parentDir of the content file prepended.
  var inputMediaFiles: seq[string] = @[]
  # Process all MDX and MD files and save them to the dist directory.
  for fileIn in cache.contentFiles.filterIt(
    (it.toLower.endsWith(MDX_EXT) or it.toLower.endsWith(MD_EXT)) and
      (appSettings.contentDir & DirSep) in it
  ):
    let fileOut =
      fileIn.replace(appSettings.contentDir & DirSep, appSettings.distDir & DirSep)

    if not appSettings.isQuiet:
      let processingMsg =
        fmt"Processing `{fileIn.relativePath(appSettings.workingDir)}` -> `{fileOut.relativePath(appSettings.workingDir)}`..."
      if logger.levelThreshold == lvlAll:
        info processingMsg
      else:
        echo processingMsg

    let fileInContents = readFile(fileIn)
    if not appSettings.isQuiet:
      info fmt"Creating output `{fileOut.parentDir}` directory..."
    if not appSettings.isDryRun:
      createDir(fileOut.parentDir)

    let outputContent = processContent(fileInContents, fileIn, appSettings)

    let inputFileDir = fileIn.parentDir()
    # Find and collect all matches of the src group for regexImage and regexVideoFile
    inputMediaFiles.add(
      fileInContents.findIter(regexImage).toSeq().mapIt(
        inputFileDir / it.captures["src"]
      )
    )
    inputMediaFiles.add(
      fileInContents.findIter(regexVideoFile).toSeq().mapIt(
        inputFileDir / it.captures["src"]
      )
    )
    if not appSettings.isDryRun:
      writeFile(fileOut, outputContent)

  # Map of input media files to output media files
  var mediaFiles: Table[string, string] = initTable[string, string]()
  var missingMediaFiles: seq[string] = @[]
  for inputMediaFile in inputMediaFiles:
    if not fileExists(inputMediaFile):
      missingMediaFiles.add(inputMediaFile)
    else:
      let outputMediaFile =
        inputMediaFile.replace(appSettings.contentDir, appSettings.distDir)
      mediaFiles[inputMediaFile] = outputMediaFile

  if appSettings.isShowingMedia:
    for inputMediaFile, outputMediaFile in mediaFiles:
      echo fmt"{inputMediaFile} -> {outputMediaFile}"
  if preprocessorErrorMessages.len() != 0:
    stderr.styledWriteLine(
      fgRed,
      fmt"Found {preprocessorErrorMessages.len()} preprocessor error messages:" & "\n" &
        preprocessorErrorMessages.join(NL),
    )
  if missingMediaFiles.len() != 0:
    stderr.styledWriteLine(
      fgRed,
      fmt"Found {missingMediaFiles.len()} missing media files:" & "\n" &
        missingMediaFiles.join(NL),
    )

when isMainModule:
  let appSettings = getAppSettings()

  if appSettings.isCleaning:
    if not appSettings.isDryRun:
      removeDir(appSettings.workingDir / appSettings.distDir)
    fmt"Removing `{appSettings.workingDir / appSettings.distDir}`. Exiting.".quit(
      QuitSuccess
    )

  echo appSettings
  process(appSettings)
  stdout.resetAttributes()
