## Auto-formats GDQuest tutorials, saving manual formatting work:
## 
## - Converts space-based indentations to tabs in code blocks.
## - Fills GDScript code comments as paragraphs.
## - Wraps symbols and numeric values in code.
## - Wraps other capitalized names, pascal case values into italics (we assume they're node names).
## - Marks code blocks without a language as using `gdscript`.
## - Add <kbd> tags around keyboard shortcuts (the form needs to be Ctrl+F1).

import std/
  [ parseopt
  , re
  , os
  , sequtils
  , strformat
  , strutils
  , sugar
  , wordwrap
  ]
import md/parser
import assets


const HelpMessage = """Auto-formats markdown documents, saving manual formatting work:

- Converts space-based indentations to tabs in code blocks.
- Fills GDScript code comments as paragraphs.
- Wraps symbols and numeric values in code.
- Wraps other capitalized names, pascal case values into italics (we assume they're node names).
- Marks code blocks without a language as using `gdscript`.
- Add <kbd> tags around keyboard shortcuts (the form needs to be Ctrl+F1).

How to use:

format_tutorials [options] <input-file> [<input-file> ...]

Options:

-i/--in-place: Overwrite the input files with the formatted output.
-o/--output-directory: Write the formatted output to the specified directory.

-h/--help: Prints this help message.
"""


const
  SupportedExtensions = ["png", "jpe?g", "mp4", "mkv", "t?res", "t?scn", "gd", "py", "shader", ]
  PatternFilenameOnly = r"(\w+\.(" & SupportedExtensions.join("|") & "))"
  PatternDirPath = r"((res|user)://)?/?([\w]+/)+(\w*\.\w+)?"
  PatternFileAtRoot = r"(res|user)://\w+\.\w+"
  PatternModifierKeys = r"Ctrl|Alt|Shift|CTRL|ALT|SHIFT|Super|SUPER"
  PatternKeyboardSingleCharacterKey = r"[A-Z0-9!@#$%^&*()_\-{}|\[\]\\;':,\./<>?]"
  PatternOtherKeys = r"F\d{1,2}|Tab|Up|Down|Left|Right|LMB|MMB|RMB|Backspace|Delete"
  PatternFunctionOrConstructorCall = r"\w+(\.\w+)*\(.*?\)"
  PatternVariablesAndProperties = r"_\w+|[a-zA-Z0-9]+([\._]\w+)+"
  PatternGodotBuiltIns = CACHE_GODOT_BUILTIN_CLASSES.join("|")

let
  RegexFilePath = re([PatternDirPath, PatternFileAtRoot, PatternFilenameOnly].join("|"))
  RegexStartOfList = re"\s*(- |\d+\. )"
  RegexMaybeCodeCommentLine = re"\s*[#/]*"
  RegexOnePascalCaseWord = re"[A-Z0-9]\w+[A-Z]\w+|[A-Z][a-zA-Z0-9]+(\.\.\.)?"
  RegexOnePascalCaseWordStrict = re"[A-Z0-9]\w+[A-Z]\w+"
  RegexMenuOrPropertyEntry = re"[A-Z0-9]+[a-zA-Z0-9]*( (-> )+[A-Z][a-zA-Z0-9]+( [A-Z][a-zA-Z0-9]*)*(\.\.\.)?)+"
  RegexCapitalWordSequence = re"[A-Z0-9]+[a-zA-Z0-9]*( (-> )?[A-Z][a-zA-Z0-9]+(\.\.\.)?)+"
  RegexKeyboardShortcut = re("((" & PatternModifierKeys & r") ?\+ ?)+(" & PatternOtherKeys & "|" & PatternKeyboardSingleCharacterKey & ")")
  RegexOneKeyboardKey = re("(" & [PatternModifierKeys, PatternOtherKeys, PatternKeyboardSingleCharacterKey].join("|") & ")")
  RegexNumber = re"\d+(D|px)|\d+(x\d+)*"
  RegexHexValue = re"(0x|#)[0-9a-fA-F]+"
  RegexCodeIdentifier = re([PatternFunctionOrConstructorCall, PatternVariablesAndProperties].join("|"))
  RegexGodotBuiltIns = re(PatternGodotBuiltIns)
  RegexSkip = re"""({%.*?%}|_.+?_|\*\*[^*]+?\*\*|\*[^*]+?\*|`.+?`|".+?"|'.+?'|\!?\[.+?\)|\[.+?\])\s*|\s+|$"""
  RegexStartOfSentence = re"\s*\p{Lu}"
  RegexEndOfSentence = re"[.!?:]\s+"
  RegexFourSpaces = re" {4}"
  RegexCodeCommentSymbol = re"#{3,}|/+"


func regexWrap(regexes: seq[Regex], pair: (string, string)): string -> (string, string)
func regexWrapEach(regexAll, regexOne: Regex; pair: (string, string)): string -> (string, string)

let formatters =
  { "any": regexWrapEach(RegexKeyboardShortcut, RegexOneKeyboardKey, ("<kbd>", "</kbd>"))
  , "any": regexWrap(@[RegexFilePath], ("`", "`"))
  , "any": regexWrap(@[RegexMenuOrPropertyEntry], ("*", "*"))
  , "any": regexWrap(@[RegexCodeIdentifier, RegexGodotBuiltIns], ("`", "`"))
  , "any": regexWrap(@[RegexNumber, RegexHexValue], ("`", "`"))
  , "any": regexWrap(@[RegexOnePascalCaseWordStrict], ("*", "*"))
  , "skipStartOfSentence": regexWrap(@[RegexCapitalWordSequence, RegexOnePascalCaseWord], ("*", "*"))
  }


type
  CommandLineArgs = object
    inputFiles: seq[string]
    inPlace: bool
    outputDirectory: string


func regexWrap(regexes: seq[Regex], pair: (string, string)): string -> (string, string) =
  ## Retruns a function that takes the string `text` and finds the first
  ## regex match from `regexes` only at the beginning of `text`.
  ##
  ## The function returns a tuple:
  ## - `(text wrapped by pair, rest of text)` if there's a regex match.
  ## - `("", text)` if there's no regex match.
  return func(text: string): (string, string) =
    for regex in regexes:
      let bound = text.matchLen(regex)
      if bound == -1: continue
      return (pair[0] & text[0 ..< bound] & pair[1], text[bound .. ^1])
    return ("", text)


func regexWrapEach(regexAll, regexOne: Regex; pair: (string, string)): string -> (string, string) =
  ## Returns a function that takes the string `text` and tries to match
  ## `regexAll` only at the beginning of `text`.
  ##
  ## The function regurns a tuple:
  ## - `(text with all occurances of RegexOne wrapped by pair, rest of text)`
  ##   if there's a regex match.
  ## - `("", text)` if there's no regex match.
  return func(text: string): (string, string) =
    let bound = text.matchLen(regexAll)
    if bound != -1:
      let replaced = replacef(text[0 ..< bound], regexOne, pair[0] & "$1" & pair[1])
      return (replaced, text[bound .. ^1])
    return ("", text)


proc formatLine(line: string): string =
  ## Returns the formatted `line` using the GDQuest standard.

  proc advance(line: string): (string, string) =
    ## Find the first `RegexSkip` and split `line` into the tuple
    ## `(line up to RegexSkip, rest of line)`.
    let (_, last) = line.findBounds(RegexSkip)
    (line[0 .. last], line[last + 1 .. ^1])

  block outer:
    var
      line = line
      isStartOfSentence = line.startsWith(RegexStartOfSentence)

    while true:
      for (applyAt, formatter) in formatters:
        if line.len <= 0: break outer
        if (applyAt, isStartOfSentence) == ("skipStartOfSentence", true): continue
        let (formatted, rest) = formatter(line)
        result &= formatted
        line = rest

      let (advanced, rest) = advance(line)
      isStartOfSentence = advanced.endsWith(RegexEndOfSentence)
      result &= advanced
      line = rest


proc formatList(lines: seq[string]): seq[string] =
  ## Returns the formatted sequence of `lines` using the GDQuest standard.
  ##
  ## `lines` is a sequence representing a markdown list. One item can span
  ## multiple lines, in which case they get concatenated before formatting.
  var
    lines = lines
    linesStart: seq[string]
    i = 0

  while i < lines.len:
    let bound = lines[i].matchLen(RegexStartOfList)
    if bound != -1:
      linesStart.add(lines[i][0 ..< bound])
      lines[i] = lines[i][bound .. ^1]
      i.inc
    else:
      lines[i - 1] &= SPACE & lines[i].strip()
      lines.delete(i)

  for (lineStart, line) in zip(linesStart, lines):
    result.add(lineStart & line.formatLine)


proc formatCodeLine(codeLine: CodeLine): string =
  ## Returns the formatted `codeLine` block using the GDQuest standard:
  ##
  ## - Converts space-based indentations to tabs.
  ## - Fills GDScript code comments as paragraphs with a max line length of 80.
  case codeLine.kind
  of clkShortcode:
    codeLine.render

  of clkRegular:
    const (TAB, HASH, SLASH, MAX_LINE_LEN) = ("\t", '#', '/', 80)
    let
      bound = max(0, codeLine.line.matchLen(RegexMaybeCodeCommentLine))
      first = codeLine.line[0 ..< bound]
      indent = first.multiReplace(
        [ (RegexFourSpaces, TAB)
        , (RegexCodeCommentSymbol, (if first.endsWith(HASH): HASH else: SLASH).repeat(2))
        ])
      sep = if indent.endsWith(HASH) or indent.endsWith(SLASH): SPACE else: ""
      margin = indent.count(TAB) + indent.strip.len + sep.len
      wrapLen = if sep == "": codeLine.line.len else: MAX_LINE_LEN - margin

    codeLine.line[bound .. ^1]
      .strip.wrapWords(wrapLen, splitLongWords=false)
      .splitLines.map(x => [indent, x].join(sep))
      .join(NL)


proc formatBlock(mdBlock: Block): string =
  ## Takes an `mdBlock` from a parsed markdown file
  ## and returns a formatted string.
  var partialResult: seq[string]

  case mdBlock.kind
  of bkCode:
    const OPEN_CLOSE = "```"
    partialResult.add(OPEN_CLOSE & mdBlock.language)
    partialResult &= mdBlock.code.map(formatCodeLine)
    partialResult.add(OPEN_CLOSE)

  of bkList:
    partialResult &= mdBlock.body.formatList

  else:
    partialResult.add(mdBlock.render)

  partialResult.join(NL)


proc formatContent*(content: string): string =
  ## Takes the markdown `content` and returns a formatted document using
  ## the GDQuest standard.
  parse(content).map(formatBlock).join(NL).strip & NL


proc parseCommandLineArguments(): CommandLineArgs =
  for kind, key, value in getopt():
    case kind
    of cmdEnd: break

    of cmdArgument:
      if fileExists(key):
        result.inputFiles.add(key)
      else:
        fmt"Invalid filename: {key}".quit

    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": echo HelpMessage
      of "in-place", "i": result.inPlace = true
      of "output-directory", "o":
        if isValidFilename(value):
          result.outputDirectory = value
        else:
          ["Invalid output directory: ", value, "", HelpMessage].join(NL).quit
      else:
        ["Invalid option: ", key, "", HelpMessage].join(NL).quit

  if result.inputFiles.len() == 0:
    ["No input files specified.", "", HelpMessage].join(NL).quit


when isMainModule:
  var args = parseCommandLineArguments()
  for file in args.inputFiles:
    let formattedContent = readFile(file).formatContent
    if args.inPlace:
      writeFile(file, formattedContent)
    else:
      echo formattedContent
