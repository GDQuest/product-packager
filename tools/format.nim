## Auto-formats GDQuest tutorials, saving manual formatting work:
## 
## - Converts space-based indentations to tabs in code blocks.
## - Fills GDScript code comments as paragraphs.
## - Wraps symbols and numeric values in code.
## - Wraps other capitalized names, pascal case values into italics (we assume they're node names).
## - Marks code blocks without a language as using `gdscript`.
## - Add <kbd> tags around keyboard shortcuts (the form needs to be Ctrl+F1).

import std/parseopt
import std/re
import std/os
import std/sequtils
import std/strutils
import std/wordwrap

import md/parser as md


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


type
    CommandLineArgs = object
        inputFiles: seq[string]
        inPlace: bool
        outputDirectory: string


func regexWrap*(regexes: seq[Regex], pair: (string, string)): auto =
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


func regexWrapEach*(regexAll, regexOne: Regex; pair: (string, string)): auto =
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


proc advanceMarkdownTextLineFormatter*(line: string): (string, string) =
    ## Find the first `RegexSkip` and split `line` into the tuple
    ## `(line up to RegexSkip, rest of line)`.
    let (_, last) = line.findBounds(RegexSkip)
    return (line[0 .. last], line[last + 1 .. ^1])


proc formatMarkdownTextLine*(line: string): string =
    ## Returns the formatted `line` using the GDQuest standard.
    let formatters =
        { "any": regexWrapEach(RegexKeyboardShortcut, RegexOneKeyboardKey, ("<kbd>", "</kbd>"))
        , "any": regexWrap(@[RegexFilePath], ("`", "`"))
        , "any": regexWrap(@[RegexMenuOrPropertyEntry], ("*", "*"))
        , "any": regexWrap(@[RegexCodeIdentifier, RegexGodotBuiltIns], ("`", "`"))
        , "any": regexWrap(@[RegexNumber, RegexHexValue], ("`", "`"))
        , "any": regexWrap(@[RegexOnePascalCaseWordStrict], ("*", "*"))
        , "skipStartOfSentence": regexWrap(@[RegexCapitalWordSequence, RegexOnePascalCaseWord], ("*", "*"))
        }
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

            let (advanced, rest) = advanceMarkdownTextLineFormatter(line)
            isStartOfSentence = advanced.endsWith(RegexEndOfSentence)
            result &= advanced
            line = rest


proc formatMarkdownTextLines*(lines: openArray[string]): string =
    ## Returns the formatted sequence of `lines` using the GDQuest standard.
    var partialResult: seq[string] = @[]
    for line in lines:
        partialResult.add(line.formatMarkdownTextLine)
    return partialResult.join("\n")


proc formatMarkdownList*(lines: seq[string]): string =
    ## Returns the formatted sequence of `lines` using the GDQuest standard.
    ##
    ## `lines` is a sequence representing a markdown list. One item can span
    ## multiple lines, in which case they get concatenated before formatting.
    var
        lines = lines
        linesStart: seq[string] = @[]
        i = 0
    while i < lines.len:
        var bound = lines[i].matchLen(RegexStartOfList)
        if bound != -1:
            linesStart.add(lines[i][0 ..< bound])
            lines[i] = lines[i][bound .. ^1]
            i.inc
        else:
            lines[i - 1] &= " " & lines[i].strip()
            lines.delete(i)

    var partialResult: seq[string] = @[]
    for (lineStart, line) in zip(linesStart, lines):
        partialResult.add(lineStart & line.formatMarkdownTextLine)
    return partialResult.join("\n")


proc formatCodeBlock*(lines: openArray[string]): string =
    ## Returns the formatted `lines` markdown code block using the GDQuest standard:
    ##
    ## - Converts space-based indentations to tabs.
    ## - Fills GDScript code comments as paragraphs with a max line length of 80.
    ## - If the code block has no language set, sets it to "gdscript".
    const TAB_WIDTH = 4
    var formattedStrings: seq[string]

    formattedStrings.add(if lines[0].strip() == "```": "```gdscript" else: lines[0])
    for line in lines[1 .. ^1]:
        var processedLine = line.replace("    ", "\t")
        if not line.match(RegexCodeCommentLine):
            formattedStrings.add(processedLine)
            continue

        var indentCount = 0
        while line[indentCount] == '\t':
            indentCount += 1

        let hashCount = processedLine[indentCount .. indentCount + 2].count("#")
        let margin = indentCount + hashCount + 1
        let desiredTextLength = 80 - indentCount * TAB_WIDTH - hashCount
        let content = wrapWords(line[margin .. ^1], desiredTextLength)
        for line in splitLines(content):
            let optionalSpace = if not line.startswith(" "): " " else: ""
            formattedStrings.add(
                repeat("\t", indentCount) &
                repeat("#", hashCount) &
                optionalSpace &
                line.strip()
             )
    return formattedStrings.join("\n")


proc convertBlocksToFormattedMarkdown*(blocks: seq[md.Block]): string =
    ## Takes a sequence of `blocks` from a parsed markdown file
    ## and returns a formatted document.
    var formattedStrings: seq[string]
    for mdBlock in blocks:
        case mdBlock.kind
            of md.bkCode: formattedStrings.add(mdBlock.render.formatCodeBlock)
            of md.bkList: formattedStrings.add(mdBlock.render.formatMarkdownList)
            of md.bkParagraph: formattedStrings.add(mdBlock.render.formatMarkdownTextLines)
            else: formattedStrings &= mdBlock.render
    result = formattedStrings.join("\n")
    result.stripLineEnd()


proc formatContent*(content: string): string =
    ## Takes the markdown `content` and returns a formatted document using
    ## the GDQuest standard.
    let parsed = md.parse(content)
    convertBlocksToFormattedMarkdown(parsed)


proc parseCommandLineArguments(): CommandLineArgs =
    for kind, key, value in getopt():
        case kind
        of cmdEnd: break
        of cmdArgument:
            if fileExists(key):
                result.inputFiles.add(key)
            else:
                echo "Invalid filename: ", key
                quit(1)
        of cmdLongOption, cmdShortOption:
            case key
            of "help", "h": echo HelpMessage
            of "in-place", "i": result.inPlace = true
            of "output-directory", "o":
                if isValidFilename(value):
                    result.outputDirectory = value
                else:
                    echo "Invalid output directory: ", value, "\n"
                    echo HelpMessage
                    quit(1)
            else:
                echo "Invalid option: ", key, "\n"
                echo HelpMessage
                quit(1)
    if result.inputFiles.len() == 0:
        echo "No input files specified.\n"
        echo HelpMessage
        quit(1)


when isMainModule:
    var args = parseCommandLineArguments()
    for file in args.inputFiles:
        let formattedContent = readFile(file).formatContent
        if args.inPlace:
            writeFile(file, formattedContent)
        else:
            echo formattedContent
