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
import md/
  [ assets
  , parser
  , utils
  ]
import types


const HELP_MESSAGE = """
{getAppFilename().extractFilename} [options] file [file...]

Auto-formats markdown documents, saving manual formatting work:

- Converts space-based indentations to tabs in code blocks.
- Fills GDScript code comments as paragraphs.
- Wraps symbols and numeric values in code.
- Wraps other capitalized names, pascal case values into italics (we assume they're node names).
- Marks code blocks without a language as using `gdscript`.
- Add <kbd> tags around keyboard shortcuts (the form needs to be Ctrl+F1).

Options:
  -i, --in-place        overwrite the input files with the formatted output.
  -h, --help            prints this help message.
  -o, --output-dir:DIR  write the formatted output to the specified directory."""


const
  SupportedExtensions = ["png", "jpe?g", "mp4", "mkv", "t?res", "t?scn", "gd", "py", "shader", ]
  PatternFilenameOnly = r"\b(\w+\.(" & SupportedExtensions.join("|") & "))\b"
  PatternDirPath = r"((res|user)://)?/?([\w]+/)+(\w*\.\w+)?"
  PatternFileAtRoot = r"(res|user)://\w+\.\w+"
  PatternModifierKeys = r"Ctrl|Alt|Shift|Super|CTRL|ALT|SHIFT|SUPER"
  PatternKeyboardSingleCharacterKey = r"[a-zA-Z0-9!@#$%^&*()_\-{}|\[\]\\;':,\./<>?]"
  PatternFKeys = r"F\d{1,2}"
  PatternOtherKeys = PatternFKeys & r"|Tab|Up|Down|Left|Right|Backspace|Delete|TAB|UP|DOWN|LEFT|RIGHT|BACKSPACE|DELETE|LMB|MMB|RMB"
  PatternFunctionOrConstructorCall = r"\w+(\.\w+)*\(.*?\)"
  PatternVariablesAndProperties = r"_\w+|[a-zA-Z0-9]+([\._]\w+)+"

let
  RegexFilePath = re([PatternDirPath, PatternFileAtRoot, PatternFilenameOnly].join("|"))
  RegexStartOfList = re"\s*(- |\d+\. )"
  RegexMaybeCodeCommentLine = re"\s*[#/]*"
  RegexOnePascalCaseWord = re"[A-Z0-9]\w+[A-Z]\w+|[A-Z][a-zA-Z0-9]+(\.\.\.)?"
  RegexOnePascalCaseWordStrict = re"[A-Z0-9]\w+[A-Z]\w+"
  RegexMenuOrPropertyEntry = re"[A-Z0-9]+[a-zA-Z0-9]*( (-> )+[A-Z][a-zA-Z0-9]+( [A-Z][a-zA-Z0-9]*)*(\.\.\.)?)+"
  RegexCapitalWordSequence = re"[A-Z0-9]+[a-zA-Z0-9]*( (-> )?[A-Z][a-zA-Z0-9]+(\.\.\.)?)+"
  RegexKeyboardFShortcut = re(PatternFKeys)
  RegexKeyboardShortcut = re("((" & PatternModifierKeys & r") ?\+ ?)+(" & PatternOtherKeys & "|" & PatternKeyboardSingleCharacterKey & ")")
  RegexOneKeyboardKey = re("(" & [PatternModifierKeys, PatternOtherKeys, PatternKeyboardSingleCharacterKey].join("|") & ")")
  RegexNumber = re"\d+(D|px)|\d+(x\d+)*"
  RegexHexValue = re"(0x|#)[0-9a-fA-F]+"
  RegexCodeIdentifier = re([PatternFunctionOrConstructorCall, PatternVariablesAndProperties].join("|"))
  RegexGodotBuiltIns = re([r"\b(", CACHE_GODOT_BUILTIN_CLASSES.join("|"), r")\b"].join)
  RegexSkip = re"""({{.*?}}|{%.*?%}|_.+?_|\*\*[^*]+?\*\*|\*[^*]+?\*|`.+?`|".+?"|'(?![vsr\h]).+?'|\!?\[.+?\)|\[.+?\])\s*|\s+|$"""
  RegexStartOfSentence = re"\s*\p{Lu}"
  RegexEndOfSentence = re"[.!?:]\s+"
  RegexFourSpaces = re" {4}"
  RegexCodeCommentSymbol = re"#{3,}|/+"


func regexWrap(regexes: seq[Regex], pair: (string, string)): string -> (string, string) =
  ## Retruns a function that takes the string `text` and finds the first
  ## regex match from `regexes` only at the beginning of `text`.
  ##
  ## The function returns a tuple:
  ## - `(text wrapped by pair, rest of text)` if there's a regex match.
  ## - `("", text)` if there's no regex match.
  let RegexBlacklist = re([r"\b(", CACHE_BLACKLIST.join("|"), r")\b\s"].join)
  return func(text: string): (string, string) =
    for regex in regexes:
      let bound = text.matchLen(regex)
      if bound == -1 or text.match(RegexBlacklist): continue
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

let formatters =
  { "any": regexWrapEach(RegexKeyboardShortcut, RegexOneKeyboardKey, ("<kbd>", "</kbd>"))
  , "any": regexWrap(@[RegexKeyboardFShortcut], ("<kbd>", "</kbd>"))
  , "any": regexWrap(@[RegexFilePath], ("`", "`"))
  , "any": regexWrap(@[RegexMenuOrPropertyEntry], ("*", "*"))
  , "any": regexWrap(@[RegexCodeIdentifier, RegexGodotBuiltIns], ("`", "`"))
  , "any": regexWrap(@[RegexNumber, RegexHexValue], ("`", "`"))
  , "any": regexWrap(@[RegexOnePascalCaseWordStrict], ("*", "*"))
  , "skipStartOfSentence": regexWrap(@[RegexCapitalWordSequence, RegexOnePascalCaseWord], ("*", "*"))
  }


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
        result.add formatted
        line = rest

      let (advanced, rest) = advance(line)
      isStartOfSentence = advanced.endsWith(RegexEndOfSentence)
      result.add advanced
      line = rest


proc formatList(items: seq[ListItem]): seq[string] = items.mapIt([it.form, it.item.formatLine].join(SPACE))


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
      .splitLines.mapIt([indent, it].join(sep))
      .join(NL)


proc formatBlock(mdBlock: Block): string =
  ## Takes an `mdBlock` from a parsed markdown file
  ## and returns a formatted string.
  var partialResult: seq[string]

  case mdBlock.kind
  of bkCode:
    const OPEN_CLOSE = "```"
    partialResult.add OPEN_CLOSE & mdBlock.language
    partialResult.add mdBlock.code.map(formatCodeLine)
    partialResult.add OPEN_CLOSE

  of bkList:
    partialResult.add mdBlock.items.formatList

  of bkParagraph:
    partialResult.add mdBlock.body.map(formatLine)

  else:
    partialResult.add(mdBlock.render)

  partialResult.join(NL)


proc formatContent*(content: string): string =
  ## Takes the markdown `content` and returns a formatted document using
  ## the GDQuest standard.
  parse(content).map(formatBlock).join(NL).strip & NL


proc getAppSettings(): AppSettingsFormat =
  for kind, key, value in getopt(shortNoVal = {'h', 'i'}, longNoVal = @["help", "in-place"]):
    case kind
    of cmdEnd: break

    of cmdArgument:
      if fileExists(key): result.inputFiles.add key
      else: fmt"Invalid filename: {key}".quit

    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": HELP_MESSAGE.quit(QuitSuccess)
      of "in-place", "i": result.inPlace = true
      of "output-dir", "o": result.outputDir = value
      else: [fmt"Invalid option: {key}", "", HELP_MESSAGE].join(NL).quit

  if result.inputFiles.len == 0: ["No input files specified.", "", HELP_MESSAGE].join(NL).quit


when isMainModule:
  let appSettings = getAppSettings()

  for filename in appSettings.inputFiles:
    let formattedContent = readFile(filename).formatContent
    if appSettings.inPlace:
      writeFile(filename, formattedContent)

    elif appSettings.outputDir != "":
      createDir(appSettings.outputDir)
      writeFile(appSettings.outputDir / filename.extractFilename, formattedContent)

    else:
      echo formattedContent

