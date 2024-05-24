# Utilities for running pandoc jobs in parallel

import std/
  [ logging
  , os
  , osproc
  , strformat
  , strutils
  , streams
  ]
import md/
  [ preprocess
  , utils
  ]
import customlogger, types


type
  PandocRunner* = object
    settings: AppSettingsBuildCourse
    processes: seq[tuple[fileIn: string, process: Process]]


proc init*(_: typedesc[PandocRunner], settings: AppSettingsBuildCourse): PandocRunner =
  result.settings = settings


proc addJob*(runner: var PandocRunner, fileIn, fileOut, fileInContents, pandocAssetsCmdOptions: string) =
  ## Add a pandoc job to the queue
  createDir(fileOut.parentDir)
  info fmt"Creating output `{fileOut.parentDir}` directory..."

  let cmd = [ runner.settings.pandocExe
            , "--self-contained"
            , "--resource-path=\"{fileIn.parentDir}\"".fmt
            , "--metadata=title:\"{fileOut.splitFile.name}\"".fmt
            , "--output=\"{fileOut}\"".fmt
            , pandocAssetsCmdOptions
            , "-"
            ].join(SPACE)

  let
    processOptions = if logger.levelThreshold == lvlAll: {poEchoCmd, poStdErrToStdOut, poUsePath, poEvalCommand} else: {poStdErrToStdOut, poUsePath, poEvalCommand}
    process = startProcess(cmd, options=processOptions)

  let input = preprocess(fileIn, fileInContents)

  process.inputStream.write input
  process.inputStream.flush()
  process.inputStream.close()

  runner.processes.add (fileIn, process)


proc waitForJobs*(runner: PandocRunner, report: var Report) =
  ## wait until all jobs are finished, then display all statuses and update the report
  for job in runner.processes:
    var outputFile: File
    discard outputFile.open(job.process.outputHandle, fmRead)

    let
      output = outputFile.readAll()
      exitCode = job.process.waitForExit()

    outputFile.close()
    job.process.close()

    if exitCode == QuitSuccess:
      report.built.inc
      if output.strip != "":
        info [fmt"`{job.fileIn.relativePath(runner.settings.workingDir)}`", "{output}".fmt].join(NL)
    else:
      report.errors.inc
      error [fmt"`{job.fileIn.relativePath(runner.settings.workingDir)}`", "{output.strip}".fmt, "Skipping..."].join(NL)
