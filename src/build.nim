import os
import strutils
import md/preprocess

const
  ContentDirectory = "content"
  OutputDirectory = "dist"

proc findAllMarkdownFiles(): seq[string] =
  for entry in walkDirRec(ContentDirectory):
    if entry.endsWith(".md"):
      result.add(entry)

proc convertMarkdownToHtml(filePath: string, outputDir: string): void =
  let fileName = filePath.extractFilename()
  let outputFilePath = outputDir / fileName.changeFileExt(".html")
  let document = readFile(filePath).runMarkdownPreprocessors()
  # TODO: replace icons
  # TODO: Run pandoc command to output the file

let markdownFiles = findAllMarkdownFiles()
for file in markdownFiles:
  convertMarkdownToHtml(file, OutputDirectory)

when isMainModule:
  if not dirExists(OutputDirectory):
    createDir(OutputDirectory)
