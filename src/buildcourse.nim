import std/
  [ logging
  , os
  , osproc
  , parseopt
  , parsecfg
  , re
  , sequtils
  , strformat
  , strutils
  , sysrand
  , terminal
  ]
import md/
  [ preprocess
  , utils
  ]
import assets
import customlogger


const
  RAND_LEN = 8 ## |
    ## `RAND_LEN` is the length of the random number sequence used to
    ## generate the temporary directory for the built-in Pandoc assets.

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
                        *Note* that DIR isn't relative to the course
                        project root directory.
  -c, --course-dir:DIR  course project directory name.
                        Default: {COURSE_DIR}.
                        *Note* that DIR is relative to the course project
                        root directory.
  -d, --dist-dir:DIR    directory name for Pandoc output.
                        Default: {DIST_DIR}.
                        *Note* that DIR is relative to the course project
                        root directory.
  -f, --force           run Pandoc even if course files are older than
                        the existing output files.
                        Default: false.
  -h, --help            print this help message.
      --clean           remove Pandoc output directory.
                        Default: false.
  -i, --ignore-dir:DIR  add DIR to a list to ignore when caching Markdown,
                        GDScript and Shader files. This option can be
                        repeated multiple times. The app ignores dot folders.
                        This option adds directories on top of that.
                        *Note*
                          - That DIR is relative to the course project
                            root directory.
                          - The Pandoc outut directory is automatically
                            added to the ignored list.
  -p, --pandoc-exe:PATH Pandoc executable path or name.
  -v, --verbose         print extra information when building the course.

Shortcodes:
  {{{{ contents [maxLevel] }}}}
    This shortcode is replaced by a Table of Contents (ToC) with links generated
    from the available headings.

    The optional `maxLevel` argument denotes the maximum heading level to include
    in the ToC.

    Note that the ToC does not include the title-level heading.

  {{{{ link fileName[.md] [text [text]] }}}}
    This shortcode is replaced by a link of the form:
    `[fileName](path-to-fileName.html)`.

    If the `text` optional argument is given, the link will take the form:
    `[text](path-to-fileName.html)`.

    Note that `text` can be a multi-word string, for example
    {{{{ link learn-to-code-how-to-ask-questions How to ask questions }}}} will result in:
    `[How to ask questions](path-to-learn-to-code-how-to-ask-questions.html)`

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


let RegexDepends = re"{(?:%|{)\h*include\h*(\H+).*\h*(?:%|})}" ## |
  ## Extract the file name or path to calculate GDScript/Shader dependencies
  ## based on the `{{ include ... }}` shortcode.


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


proc getTempDir(workingDir: string): string =
  ## Returns a random directory name in the `workingDir` folder.
  ## For example: `workingDir/tmp-12345678`.
  workingDir / ["tmp-", urandom(RAND_LEN).join[0 ..< RAND_LEN]].join


proc resolveWorkingDir(appSettings: AppSettings): AppSettings =
  ## Tries to find the root directory of the course project by checking
  ## either `CFG_FILE` or `appSettings.courseDir` exist.
  ##
  ## If a valid course project was found it returns the updated
  ## `AppSettings.workingDir`.
  result = appSettings
  for dir in appSettings.inputDir.parentDirs:
    if (dir / CFG_FILE).fileExists or (dir / result.courseDir).dirExists:
      result.workingDir = dir
      break


proc resolveAppSettings(appSettings: AppSettings): AppSettings =
  ## Fills `AppSettings` with either defaults or values found in `CFG_FILE`
  ## if it exists and there were no matching command line arguments given.
  ##
  ## Returns the updated `AppSettings` object.
  ##
  ## *Note* that it also stops the execution if there was an error with
  ## the given values.
  result = appSettings
  if result.courseDir == "": result.courseDir = COURSE_DIR
  if result.distDir == "": result.distDir = DIST_DIR
  if result.pandocExe == "": result.pandocExe = PANDOC_EXE
  result = resolveWorkingDir(result)

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
      .mapIt("\t{result.workingDir / it}".fmt)

    if ignoreDirsErrors.len != 0:
      warn ("Invalid ignore directories:" & ignoreDirsErrors).join(NL)

    result.ignoreDirs.add result.distDir


proc getAppSettings(): AppSettings =
  ## Returns an `AppSettings` object with appropriate values. It stops the
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
      of "ignore-dir", "i": result.ignoreDirs.add value
      of "pandoc-exe", "p": result.pandocExe = value
      of "pandoc-assets-dir", "a": result.pandocAssetsDir = value 
      of "verbose", "v": logger.levelThreshold = lvlAll
      else: [ fmt"Unrecognized command line option: `{key}`."
            , ""
            , "Help:"
            , HELP_MESSAGE.fmt
            , "Exiting."
            ].join(NL).quit

  result = result.resolveAppSettings


proc process(appSettings: AppSettings) =
  ## Main function that processes the Markdown files from
  ## `appSettings.courseDir` with Pandoc and the internal preprocessor.
  let
    tmpDir = getTempDir(appSettings.workingDir)
    pandocAssetsCmdOptions = block:
      if appSettings.pandocAssetsDir == "":
        let
          courseCssFile = tmpDir / CACHE_COURSE_CSS_NAME
          gdscriptDefFile = tmpDir / CACHE_GDSCRIPT_DEF_NAME
          gdscriptThemeFile = tmpDir / CACHE_GDSCRIPT_THEME_NAME

        createDir(tmpDir)
        info fmt"Creating temporary directory `{tmpDir}`..."

        writeFile(courseCssFile, CACHE_COURSE_CSS)
        writeFile(gdscriptDefFile, CACHE_GDSCRIPT_DEF)
        writeFile(gdscriptThemeFile, CACHE_GDSCRIPT_THEME)

        [ "--css=\"{courseCssFile}\"".fmt
        , "--syntax-definition=\"{gdscriptDefFile}\"".fmt
        , "--highlight-style=\"{gdscriptThemeFile}\"".fmt
        ].join(SPACE)

      else:
        [ "--css=\"{appSettings.pandocAssetsDir / CACHE_COURSE_CSS_NAME}\"".fmt
        , "--syntax-definition=\"{appSettings.pandocAssetsDir / CACHE_GDSCRIPT_DEF_NAME}\"".fmt
        , "--highlight-style=\"{appSettings.pandocAssetsDir / CACHE_GDSCRIPT_THEME_NAME}\"".fmt
        ].join(SPACE)

  defer:
    # The `defer` block always run at the end of the function.
    if dirExists(tmpDir):
      info ""
      info fmt"Removing temporary directory `{tmpDir}`..."
      removeDir(tmpDir)

  # Prepare the global `cache` for `appSettings.workingDir`.
  cache = prepareCache(appSettings.workingDir, appSettings.courseDir, appSettings.ignoreDirs)
  for fileIn in cache.files.filterIt(
    it.toLower.endsWith(MD_EXT) and
    (appSettings.courseDir & DirSep) in it
  ):
    let
      fileIn = appSettings.workingDir / fileIn
      fileOut = fileIn.multiReplace(
        (appSettings.courseDir & DirSep, appSettings.distDir & DirSep),
        (MD_EXT, HTML_EXT)
      )

    var processingMsg = fmt"Processing `{fileIn}` -> `{fileOut}`..."
    if logger.levelThreshold == lvlAll:
      info ""
      info processingMsg
    else:
      echo ""
      echo processingMsg

    let
      fileInContents = readFile(fileIn)
      doProcess = (
        appSettings.isForced or
        not fileExists(fileOut) or
        fileIn.fileNewer(fileOut) or
        fileInContents.getDepends.anyIt(it.fileNewer(fileOut))
      )

    processingMsg = fmt"`{fileIn}` and its dependencies are older than `{fileOut}`. Skipping..."
    if doProcess:
      createDir(fileOut.parentDir)
      info fmt"Creating output `{fileOut.parentDir}` directory..."

      let cmd = [ appSettings.pandocExe
                , "--self-contained"
                , "--resource-path=\"{fileIn.parentDir}\"".fmt
                , "--metadata=title:\"{fileOut.splitFile.name}\"".fmt
                , "--output=\"{fileOut}\"".fmt
                , pandocAssetsCmdOptions
                , "-"
                ].join(SPACE)

      let
        processOptions = if logger.levelThreshold == lvlAll: {poEchoCmd, poStdErrToStdOut} else: {poStdErrToStdOut}
        pandocResult = execCmdEx(cmd, processOptions, input = preprocess(fileIn, fileInContents))

      if pandocResult.output.strip != "" and pandocResult.exitCode == QuitSuccess:
        info [fmt"`{fileIn}`", "{pandocResult.output}".fmt].join(NL)

      elif pandocResult.exitCode != QuitSuccess:
        error [fmt"`{fileIn}`", "{pandocResult.output.strip}".fmt, "Skipping..."].join(NL)

    elif logger.levelThreshold == lvlAll:
      info processingMsg

    else:
      echo processingMsg


when isMainModule:
  let appSettings = getAppSettings()
  info appSettings

  if appSettings.isCleaning:
    removeDir(appSettings.workingDir / appSettings.distDir)
    fmt"Removing `{appSettings.workingDir / appSettings.distDir}`. Exiting.".quit(QuitSuccess)

  process(appSettings)
  stdout.resetAttributes()

