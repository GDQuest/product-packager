import std/algorithm
import std/terminal

type
  ErrorSeverity* = enum
    Warning
    Error

  ErrorKind* = enum
    Generic
    MissingMedia
    MissingFile

  ErrorEntry* = object
    message: string
    severity: ErrorSeverity
    filepath: string
    lineNumber: int
    kind: ErrorKind
    context: string
      ## Optional extra context to help the user understand the error.
      ## Use this for instance when including a snippet of code, to show the
      ## user where the error occurred in the code.

  ErrorLog* = object
    entries: seq[ErrorEntry]

var globalErrorLog: ErrorLog
var showWarnings = false

proc addError*(
    message: string,
    filepath: string,
    lineNumber: int = 0,
    kind: ErrorKind = ErrorKind.Generic,
    context: string = "",
) =
  ## Registers an error in the global error log.
  globalErrorLog.entries.add(
    ErrorEntry(
      message: message,
      severity: ErrorSeverity.Error,
      filepath: filepath,
      lineNumber: lineNumber,
      kind: kind,
      context: context,
    )
  )

proc addWarning*(message: string, filepath: string, lineNumber: int = 0) =
  ## Registers a warning in the global error log.
  globalErrorLog.entries.add(
    ErrorEntry(
      message: message,
      severity: ErrorSeverity.Warning,
      filepath: filepath,
      lineNumber: lineNumber,
    )
  )

proc hasErors*(): bool =
  for entry in globalErrorLog.entries:
    if entry.severity >= ErrorSeverity.Error:
      return true
  false

proc printErrors(entries: seq[ErrorEntry]) =
  for entry in entries:
    let location =
      if entry.lineNumber > 0:
        entry.filepath & ":" & $entry.lineNumber
      else:
        entry.filepath

    let prefix =
      case entry.severity
      of ErrorSeverity.Warning: "[WARNING]"
      of ErrorSeverity.Error: "[ERROR]"
    var message = prefix & " at " & location & ": " & entry.message & "\n"
    if entry.context != "":
      message.add(" -> context: " & entry.context & "\n")

    let color =
      case entry.severity
      of ErrorSeverity.Warning: fgYellow
      of ErrorSeverity.Error: fgRed
    stdout.styledWrite(color, message)

proc printReport*() =
  ## Sorts errors by file and line number and prints them to the console.
  let issueCount = globalErrorLog.entries.len
  if issueCount == 0:
    return

  stderr.styledWriteLine(
    fgRed,
    """

============
Error Report
============
""",
  )

  var sortedEntries = globalErrorLog.entries
  sortedEntries.sort do(a, b: ErrorEntry) -> int:
    result = cmp(a.filepath, b.filepath)
    if result == 0:
      result = cmp(a.lineNumber, b.lineNumber)

  # Separate entries into two sequences
  var nonMediaErrors: seq[ErrorEntry]
  var mediaErrors: seq[ErrorEntry]

  for entry in sortedEntries:
    if not showWarnings and entry.severity == ErrorSeverity.Warning:
      continue

    if entry.kind == ErrorKind.MissingMedia:
      mediaErrors.add(entry)
    else:
      nonMediaErrors.add(entry)

  stderr.styledWriteLine(
    fgRed,
    "Found " & $(nonMediaErrors.len + mediaErrors.len) & " issues in total." & "\n",
  )
  printErrors(nonMediaErrors)
  if mediaErrors.len() != 0:
    stderr.styledWriteLine(
      fgRed, "There are " & $mediaErrors.len & " missing media files:" & "\n"
    )
    printErrors(mediaErrors)

  stdout.resetAttributes()
