# Auto-formats our tutorials, saving manual formatting work:
# 
# - Converts space-based indentations to tabs in code blocks.
# - Fills GDScript code comments as paragraphs.
# - Wraps symbols and numeric values in code.
# - Wraps other capitalized names, pascal case values into italics (we assume they're node names).
# - Marks code blocks without a language as using `gdscript`.
# - Add <kbd> tags around keyboard shortcuts (the form needs to be Ctrl+F1).

import std/parseopt
import std/re
import std/os
import std/strutils
import std/sequtils
import std/wordwrap

import godot_built_ins

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

    BlockKind = enum
        TextParagraph,
        CodeBlock,
        YamlFrontMatter,
        Table,
        List,
        Blockquote,
        Heading,
        EmptyLine,
        Reference,
        Html,
        GDQuestShortcode

    Block = ref object
        kind: BlockKind
        text: seq[string]


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
    PatternGodotBuiltIns = GodotBuiltInClassesByLength.join("|")

let
    RegexFilePath = re([PatternDirPath, PatternFileAtRoot, PatternFilenameOnly].join("|"))
    RegexStartOfList = re"- |\d+\. "
    RegexCodeCommentLine = re"\s*#"
    RegexOnePascalCaseWord = re"[A-Z0-9]\w+[A-Z]\w+|[A-Z][a-zA-Z0-9]+(\.\.\.)?"
    RegexOnePascalCaseWordStrict = re"[A-Z0-9]\w+[A-Z]\w+"
    RegexCapitalWordSequence = re"[A-Z0-9]+[a-zA-Z0-9]*( (-> )?[A-Z][a-zA-Z0-9]+(\.\.\.)?)+"
    RegexKeyboardShortcut = re("((" & PatternModifierKeys & r") ?\+ ?)+(" & PatternOtherKeys & "|" & PatternKeyboardSingleCharacterKey & ")")
    RegexOneKeyboardKey = re("(" & [PatternModifierKeys, PatternOtherKeys, PatternKeyboardSingleCharacterKey].join("|") & ")")
    RegexNumber = re"\d+"
    RegexHexValue = re"(0x|#)[0-9a-fA-F]+"
    RegexCodeIdentifier = re([PatternFunctionOrConstructorCall, PatternVariablesAndProperties].join("|"))
    RegexGodotBuiltIns = re(PatternGodotBuiltIns)


func regexWrap(regexes: seq[Regex], pair: (string, string)): auto =
    return func(text: string): (string, int, int) =
        for regex in regexes:
            let bounds = findBounds(text, regex)
            if bounds == (-1, 0): continue
            let (first, last) = bounds
            return (pair[0] & text[first .. last] & pair[1], first, last + 1)
        return ("", -1, -1)


func regexWrapEach(regexAll, regexOne: Regex; pair: (string, string)): auto =
    return func(text: string): (string, int, int) =
        let bounds = findBounds(text, regexAll)
        if bounds != (-1, 0):
            let
                (first, last) = bounds
                toFormat = text[first .. last]
                replaced = replacef(toFormat, regexOne, pair[0] & "$1" & pair[1])
            return (replaced, first, last + 1)
        return ("", -1, -1)



func formatMarkdownTextLine(line: string, formatters: openArray[auto]): seq[string] =
    var
        line = line
        index = 0
    while index < formatters.len:
        let formatted = formatters[index](line)
        if formatted == ("", -1, -1):
            index = index.succ
            continue
        let (text, first, last) = formatted
        result &= @[line[0 ..< first], text]
        line = line[last .. ^1]
    result.add(line)


proc formatMarkdownTextLines(lines: seq[string]): string =
    # Order:
    # 1. Keyboard shortcuts
    # 2. Paths
    # 3. Code
    # 4. Numbers
    # 5. Capital words
    let formatters =
        [ regexWrapEach(RegexKeyboardShortcut, RegexOneKeyboardKey, ("<kbd>", "</kbd>"))
        , regexWrap(@[RegexFilePath], ("`", "`"))
        , regexWrap(@[RegexCodeIdentifier, RegexGodotBuiltIns], ("`", "`"))
        , regexWrap(@[RegexNumber, RegexHexValue], ("`", "`"))
        , regexWrap(@[RegexCapitalWordSequence, RegexOnePascalCaseWord], ("*", "*"))
        ]

    for line in lines:
        var formatted = formatMarkdownTextLine(line, formatters).filter(proc(x: string): bool = x != "")
        if not formatted[0].contains(RegexOnePascalCaseWordStrict):
            formatted[0] = formatted[0].replace("*")
        result &= formatted.join & "\n"


proc formatMarkdownList(lines: seq[string]): string =
    ## Formats the text of a list markdown block (ordered or unordered) and
    ## returns the formatted string.
    ##
    ## For each list item:
    ##
    ## - Italicizes a single capital word with nothing after it.
    ## - Italicizes a sequence of capital words at the start.
    ## - Formats the rest of the text like a regular sentence.
    var formattedLines: seq[string]
    for line in lines:
        let (listStartIndex, lineStart) = findBounds(line, RegexStartOfList)
        if listStartIndex == -1:
            formattedLines.add(formatMarkdownTextLines(@[line]))
            continue

        let listStart = line.substr(0, lineStart)
        var text = line.substr(lineStart).strip()
        let isSingleWord = text.count(" ") == 0
        if isSingleWord:
            text = "_" & text & "_"
        else:
            let (matchStart, matchEnd) = findBounds(text, RegexCapitalWordSequence)
            if matchStart == 0:
                let match = text.substr(0, matchEnd)
                text = "_" & match & "_" & formatMarkdownTextLines(@[
                        text.substr(matchEnd)])

        formattedLines.add(listStart & text)
    result = formattedLines.join("\n")


proc formatCodeBlock(lines: seq[string]): string =
    ## Formats the content of a markdown code block:
    ##
    ## - Converts space-based indentations to tabs in code blocks.
    ## - Fills GDScript code comments as paragraphs with a max line length of 80.
    ## - If the block has no language set, sets it to "gdscript".
    ##
    ## `text` should be the text of the code block with the triple backtick
    ## lines>.
    var formattedStrings: seq[string]

    let firstLine = (if lines[0].strip() == "```": "```gdscript" else: lines[0])
    formattedStrings.add(firstLine)
    for line in lines[1 .. ^1]:
        var processedLine = line.replace("    ", "\t")
        if not line.match(RegexCodeCommentLine):
            formattedStrings.add(processedLine)
            continue

        var indentCount = 0
        while line[indentCount] == '\t':
            indentCount += 1
        const tabWidth = 4

        let hashCount = processedLine[indentCount .. indentCount + 2].count("#")
        let margin = indentCount + hashCount + 1
        let desiredTextLength = 80 - indentCount * tabWidth - hashCount
        let content = wrapWords(line[margin .. ^1], desiredTextLength,
                newline = "\n")
        for line in splitLines(content):
            let optionalSpace = if not line.startswith(" "): " " else: ""
            formattedStrings.add(repeat("\t", indentCount) & repeat("#",
                    hashCount) & optionalSpace & line.strip())
    result = formattedStrings.join("\n")


proc convertBlocksToFormattedMarkdown(blocks: seq[Block]): string =
    ## Takes a sequence of blocks from a parsed markdown file and returns a
    ## formatted document.
    const IgnoredBlockKinds = [EmptyLine, YamlFrontMatter, Blockquote, Heading,
            Table, GDQuestShortcode, Reference, Html]
    var formattedStrings: seq[string]
    for mdBlock in blocks:
        case mdBlock.kind:
            of IgnoredBlockKinds:
                formattedStrings.add(mdBlock.text)
            of CodeBlock:
                formattedStrings.add(formatCodeBlock(mdBlock.text))
            of List:
                formattedStrings.add(formatMarkdownList(mdBlock.text))
            else:
                formattedStrings.add(formatMarkdownTextLines(mdBlock.text))
    result = formattedStrings.join("\n")
    result.stripLineEnd()


proc parseBlocks(content: string): seq[Block] =
    ## Parses a markdown document into a sequence of blocks.
    ##
    ## This is a limited block parser that ignores many markdown features.
    ## For example, it doesn't parse recursive blocks.
    ##
    ## It's designed specifically to parse the markdown content of the tutorials
    ## for formatting.
    proc createDefaultBlock(): Block =
        return Block(
            kind: TextParagraph,
            text: @[],
        )

    # Make the sequence big enough to avoid resizing too many times.
    var currentBlock = createDefaultBlock()
    var previousLine = ""
    for line in splitLines(content):
        let
            isEmptyLine = line.strip() == ""
            isClosingParagraph = currentBlock.kind == TextParagraph and
                    currentBlock.text.len() != 0

        if not isEmptyLine:
            currentBlock.text.add(line)

        if isEmptyLine and isClosingParagraph:
            result.add(currentBlock)
            currentBlock = createDefaultBlock()
        # Lines starting with a hash could be comments inside a code block
        elif line.startswith("#") and currentBlock.kind != CodeBlock:
            currentBlock.kind = Heading
            result.add(currentBlock)
            currentBlock = createDefaultBlock()
        elif line.startswith("```"):
            if currentBlock.kind == TextParagraph:
                currentBlock.kind = CodeBlock
            elif currentBlock.kind == CodeBlock:
                result.add(currentBlock)
                currentBlock = createDefaultBlock()
        elif line.startswith("---"):
            if currentBlock.kind == TextParagraph:
                currentBlock.kind = YamlFrontMatter
            elif currentBlock.kind == YamlFrontMatter:
                result.add(currentBlock)
                currentBlock = createDefaultBlock()
        elif line.startsWith("{%") and currentBlock.kind == TextParagraph:
            currentBlock.kind = GDQuestShortcode
        elif line.startsWith("["):
            currentBlock.kind = Reference
            currentBlock = createDefaultBlock()
        elif line.startsWith("<") and currentBlock.kind != Html:
            currentBlock.kind = Html
        elif line.startsWith(">") and currentBlock.kind != Blockquote:
            currentBlock.kind = Blockquote
        elif line.match(RegexStartOfList):
            currentBlock.kind = List
        elif line.startsWith("|"):
            currentBlock.kind = Table

        if isEmptyLine:
            let isClosingBlock = currentBlock.kind in @[List, Html, Table, Blockquote] or (
                    currentBlock.kind == GDQuestShortcode and
                    previousLine.strip().endsWith("%}"))
            if isClosingBlock:
                result.add(currentBlock)
                currentBlock = createDefaultBlock()

            currentBlock.kind = EmptyLine
            currentBlock.text = @[""]
            result.add(currentBlock)
            currentBlock = createDefaultBlock()

        previousLine = line
    # When the file ends, we need to close the last block.
    result.add(currentBlock)


proc formatContent*(content: string): string =
    let blocks = parseBlocks(content)
    return convertBlocksToFormattedMarkdown(blocks)


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
        let
            content = readFile(file)
            formattedContent = formatContent(content)
        if args.inPlace:
            writeFile(file, formattedContent)
        else:
            echo formattedContent
