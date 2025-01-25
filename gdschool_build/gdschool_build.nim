## Program to preprocess mdx files for GDQuest courses on GDSchool.
## Replaces include shortcodes with the contents of the included source code files.
## It also inserts components representing Godot icons in front of Godot class names.
import std/[os, sequtils, strformat, strutils, terminal, nre, tables, times, sets]
import preprocessor/preprocessor
import preprocessor/cache
import settings
import errors

proc hasFileChanged(pathSrc, pathDist: string): bool =
  ## Returns `true` if the source file has been accessed or modified since the destination file was last modified.
  ## For non-existent destination files, it returns `true`.
  if not fileExists(pathDist):
    return true

  # For mdx files, they get modified during the build process, so we can't
  # compare the input and output file size or hash. So, we compare the last
  # access and modification times.
  return
    pathSrc.getLastAccessTime() > pathDist.getLastModificationTime() or
    pathSrc.getLastModificationTime() > pathDist.getLastModificationTime()

proc process(appSettings: BuildSettings) =
  # This cache lists code files (.gd, .gdshader) in the content directory and maps associated files.
  cache.fileCache = cache.prepareCache(appSettings)
  type ProcessedFile = object
    inputPath: string
    content: string
    outputPath: string

  var
    processedFiles: seq[ProcessedFile] = @[]
    # This table maps media files found in content to their destination paths.
    mediaFiles: Table[string, string] = initTable[string, string]()
    missingMediaFiles: HashSet[string] = initHashSet[string]()

  let pathPartContent = appSettings.contentDir & DirSep
  let pathPartReplace =
    if appSettings.outContentDir.len() != 0:
      appSettings.distDir & DirSep & appSettings.outContentDir & DirSep & pathPartContent
    else:
      appSettings.distDir & DirSep & pathPartContent
  # Process all MDX and MD files and save them to the dist directory.
  for fileIn in cache.fileCache.contentFiles:
    let fileOut = fileIn.replace(pathPartContent, pathPartReplace)

    # Preprocessing and writing files only happens if the file has changed,
    # but we need to read the file contents to find the media files it uses and which are missing.
    let fileInContents = readFile(fileIn)
    let inputFileDir = fileIn.parentDir()

    let filePathRelative = fileIn.relativePath(appSettings.projectDir)
    if appSettings.isForced or hasFileChanged(fileIn, fileOut):
      if not appSettings.isQuiet:
        let processingMsg =
          fmt"Processing `{filePathRelative}` -> `{fileOut.relativePath(appSettings.projectDir)}`..."
        echo processingMsg

      let htmlAbsoluteMediaDir = "/media/courses/" & inputFileDir
      let outputContent = preprocessor.processContent(
        fileInContents, inputFileDir, htmlAbsoluteMediaDir, appSettings,
        filePathRelative,
      )

      processedFiles.add(
        ProcessedFile(inputPath: fileIn, content: outputContent, outputPath: fileOut)
      )

    # Collect media files found in the content.
    # TODO: eventually this should be collected after parsing the MDX files, to
    # have access to line numbers in case of errors.
    let distDirMedia =
      appSettings.distDir / "public" / "media" / "courses" / inputFileDir
    var inputMediaFiles: seq[string] =
      fileInContents.findIter(regexMarkdownImage).toSeq().mapIt(it.captures["path"])
    inputMediaFiles.add(
      fileInContents.findIter(regexVideoFile).toSeq().mapIt(it.captures["src"])
    )
    for mediaFile in inputMediaFiles:
      let inputPath = inputFileDir / mediaFile
      if fileExists(inputPath):
        let outputPath = distDirMedia / mediaFile
        if hasFileChanged(inputPath, outputPath):
          mediaFiles[inputPath] = outputPath
      elif not missingMediaFiles.contains(inputPath):
        missingMediaFiles.incl(inputPath)
        errors.addError(
          message = "Missing media file: " & inputPath,
          filepath = fileIn,
          kind = ErrorKind.MissingMedia,
        )

  # Show all media files processed and output collected errors
  if appSettings.isShowingMedia:
    for inputMediaFile, outputMediaFile in mediaFiles:
      echo fmt"{inputMediaFile} -> {outputMediaFile}"

  if hasErors():
    errors.printReport()

  # Create directories and write files to output directory
  if not appSettings.isDryRun and not appSettings.isShowingMedia:
    for processedFile in processedFiles:
      createDir(processedFile.outputPath.parentDir())
      writeFile(processedFile.outputPath, processedFile.content)

    for inputMediaFile, outputMediaFile in mediaFiles:
      createDir(outputMediaFile.parentDir())
      copyFile(inputMediaFile, outputMediaFile)

when isMainModule:
  let appSettings = settings.getAppSettings()

  if appSettings.isCleaning:
    if not appSettings.isDryRun:
      removeDir(appSettings.projectDir / appSettings.distDir)
    fmt"Removing `{appSettings.projectDir / appSettings.distDir}`. Exiting.".quit(
      QuitSuccess
    )

  echo appSettings
  process(appSettings)
  stdout.resetAttributes()
