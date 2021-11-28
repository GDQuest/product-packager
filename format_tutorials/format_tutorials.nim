# Auto-formats our tutorials, saving manual formatting work:
# 
# - Converts space-based indentations to tabs in code blocks.
# - Fills GDScript code comments as paragraphs.
# - Wraps symbols and numeric values in code.
# - Wraps other capitalized names, pascal case values into italics (we assume they're node names).
# - Marks code blocks without a language as using `gdscript`.
# - Add <kbd> tags around keyboard shortcuts (the form needs to be Ctrl+F1).

import std/os
import std/strutils
import std/parseopt
import std/re
import std/wordwrap


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
        text: string


const
    SupportedExtensions = @["png", "jpe?g", "mp4", "mkv", "t?res",
        "t?scn", "gd", "py", "shader", ]
    PatternFilenameOnly = r"(\w+\.(" & SupportedExtensions.join("|") & "))"
    PatternDirPath = r"((res|user)://)?/?([\w]+/)+(\w*\.\w+)?"
    PatternFileAtRoot = r"(res|user)://\w+\.\w+"
    PatternModifierKeys = r"Ctrl|Alt|Shift|CTRL|ALT|SHIFT|Super|SUPER"
    PatternKeyboardSingleCharacterKey = r"[A-Z0-9!@#$%^&*()_+\-{}|\[\]\\;':,\./<>?]"
    PatternOtherKeys = r"Tab|Up|Down|Left|Right|LMB|MMB|RMB|Backspace|Delete"

let
    RegexFilePath = re(@[PatternDirPath, PatternFileAtRoot,
            PatternFilenameOnly].join("|"))
    RegexStartOfList = re"- |\d+\. "
    RegexCodeCommentLine = re"\s*#"
    RegexOnePascalCaseWord = re"[A-Z0-9]\w+[A-Z]\w+|[A-Z][a-zA-Z0-9]+(\.\.\.)?"
    RegexCapitalWordSequence = re"[A-Z0-9]+[a-zA-Z0-9]*( (-> )?[A-Z][a-zA-Z0-9]+(\.\.\.)?)+"
    RegexKeyboardShortcut = re("((" & PatternModifierKeys &
            r") ?\+ ?)+(F\d{1,2}|" & PatternKeyboardSingleCharacterKey & "|" &
            PatternOtherKeys & ")")
    RegexOneKeyboardKey = re("(" & PatternModifierKeys & "|" &
            PatternKeyboardSingleCharacterKey & "|" & PatternOtherKeys & ")")
    RegexNumber = re"\d+"
    RegexHexValue = re"(0x|#)[0-9a-fA-F]+"
    RegexCodeIdentifier = re"TEMPSTRING"


proc regexWrapAtPosition(text: string, startPosition: int, regexes: seq[Regex],
        wrapPair: (string, string)): (string, int) =
    ## Applies a series of regexes to the text starting at `startPosition`,
    ## wrapping the matches with the given `wrapPair`.
    ##
    ## If a regex matches the text, returns the new text and the end position of
    ## the formatted portion in the original `text`.
    ##
    ## If no regex matches the text, returns the input `text` and `-1`.
    var 
        outText = ""
        outPosition = -1
        previousPosition = startPosition
    for regex in regexes:
        var (first, last) = findBounds(text, regex, previousPosition)
        if first < 0: continue
        outText.add(substr(text, previousPosition, first-1))
        let wrappedText = wrapPair[0] & text[first .. last] & wrapPair[1]
        outText.add(wrappedText)
        previousPosition = last + 1
        outPosition = previousPosition
        break
    add(outText, substr(text, previousPosition))
    return (outText, outPosition)


proc formatKeyboardShortcuts(text: string, position: int): (string, int) =
    let (matchStart, matchEnd) = findBounds(text, RegexKeyboardShortcut, position)
    if matchStart != -1:
        let toFormat = text[matchStart .. matchEnd]
        let outputText = re.replacef(toFormat, RegexOneKeyboardKey, "<kbd>$1</kbd>")
        return (outputText, matchEnd)
    return (text, -1)


proc formatCode(text: string, position: int): (string, int) =
    let regexes = @[RegexCodeIdentifier]
    regexWrapAtPosition(text, position, regexes, ("`", "`"))


proc formatNumbers(text: string, position: int): (string, int) =
    let regexes = @[RegexNumber, RegexHexValue]
    regexWrapAtPosition(text, position, regexes, ("`", "`"))


proc formatFilePaths(text: string, position: int): (string, int) =
    let regexes = @[RegexFilePath]
    regexWrapAtPosition(text, position, regexes, ("`", "`"))


proc formatCapitalWords(text: string, position: int): (string, int) =
    let regexes = @[RegexCapitalWordSequence, RegexOnePascalCaseWord]
    regexWrapAtPosition(text, position, regexes, ("*", "*"))


proc formatMarkdownTextLines(text: string): string =
    ## Formats regular lines of text, running them through multiple formatting
    ## functions.
    ##
    ## Returns the formatted text.
    const FormatPairs = [ ("*", "*"), ("**", "**"), ("_", "_"), ("`", "`"),
        ("\"", "\""), ("'", "'"), ("[", "]"), ("[", ")"), ("![", ")")]
    const Formatters = [
        formatCode,
        formatCapitalWords,
        formatKeyboardShortcuts,
        formatFilePaths,
        formatNumbers,
    ]
    for line in text.splitLines():
        block outerLoop:
            # We check to apply formatters from the first non-whitespace character.
            # We walk forward in the string and track the position IN THE INPUT
            # `text`. This is simpler than constantly updating the output string
            # length and calculate new positions as we format regions.
            var
                position = 0
                previousPosition = 0
            let endPosition = line.len()
            while position != endPosition:
                block innerLoop:
                    if position == endPosition: break outerLoop
                    while line[position] == ' ':
                        position += 1

                    # We want to skip already formatted parts or text inside quotes.
                    for (first, last) in FormatPairs:
                        if line.find(first, position) == position:
                            let endPosition = line.find(last, position + 1)
                            if endPosition != -1:
                                position = endPosition + last.len()
                                result &= line[previousPosition .. position-1]
                                previousPosition = position
                                break innerLoop

                    for formatter in Formatters:
                        let (formattedText, endPosition) = formatter(line, position)
                        if endPosition != -1:
                            result &= formattedText[0 .. endPosition - position-1]
                            #echo "Previous: ", previousPosition, " Position: ", position, " End: ", endPosition, " Length:", line.len()
                            previousPosition = position
                            position = endPosition
                            break innerLoop

                    let nextSpace = find(line, ' ', position)
                    if nextSpace == -1:
                        result &= line[position .. ^1]
                        break outerLoop
                    else:
                        result &= line[previousPosition .. position-1]
                        previousPosition = position
                        position = nextSpace + 1
                
    result = text


proc formatMarkdownList(listText: string): string =
    ## Formats the text of a list markdown block (ordered or unordered) and
    ## returns the formatted string.
    ##
    ## For each list item:
    ##
    ## - Italicizes a single capital word with nothing after it.
    ## - Italicizes a sequence of capital words at the start.
    ## - Formats the rest of the text like a regular sentence.
    var formattedLines: seq[string]
    for line in listText.splitLines():
        let (listStartIndex, lineStart) = re.findBounds(line, RegexStartOfList)
        if listStartIndex == -1:
            formattedLines.add(formatMarkdownTextLines(line))
            continue

        let listStart = line.substr(0, lineStart)
        var text = line.substr(lineStart).strip()
        let isSingleWord = text.count(" ") == 0
        if isSingleWord:
            text = "_" & text & "_"
        else:
            let (matchStart, matchEnd) = re.findBounds(text, RegexCapitalWordSequence)
            if matchStart == 0:
                let match = text.substr(0, matchEnd)
                text = "_" & match & "_" & formatMarkdownTextLines(text.substr(matchEnd))

        formattedLines.add(listStart & text)
    result = formattedLines.join("\n")


proc formatCodeBlock(text: string): string =
    ## Formats the content of a markdown code block:
    ##
    ## - Converts space-based indentations to tabs in code blocks.
    ## - Fills GDScript code comments as paragraphs with a max line length of 80.
    ## - If the block has no language set, sets it to "gdscript".
    ##
    ## `text` should be the text of the code block with the triple backtick
    ## lines>.
    var formattedStrings: seq[string]
    let lines = text.splitLines()

    let firstLine = (if lines[0].strip() == "```": "```gdscript" else: lines[0])
    formattedStrings.add(firstLine)
    for line in lines[1 .. ^1]:
        var processedLine = line.replace("    ", "\t")
        if not line.match(RegexCodeCommentLine):
            formattedStrings.add(processedLine)
            continue

        var indentCount = 0
        while text[indentCount] == '\t':
            indentCount += 1
        let indentSize = indentCount * 4

        let hashCount = processedLine[indentCount .. indentCount + 2].count("#")
        let margin = indentSize + hashCount
        let content = wrapWords(line[margin .. ^1], 80 - margin)
        for line in splitLines(content):
            formattedStrings.add(repeat("\t", indentCount) & repeat("#", hashCount) & line)

        formattedStrings.add(processedLine)

    result = formattedStrings.join("\n")


proc convertBlocksToFormattedMarkdown(blocks: seq[Block]): string =
    ## Takes a sequence of blocks from a parsed markdown file and returns a
    ## formatted document.
    const IgnoredBlockKinds = [EmptyLine, YamlFrontMatter, Blockquote, Heading,
            Table, GDQuestShortcode, Reference]
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
            text: "",
        )

    # Make the sequence big enough to avoid resizing too many times.
    var currentBlock = createDefaultBlock()
    var previousLine = ""
    for line in splitLines(content):
        let
            isEmptyLine = line.strip() == ""
            isClosingParagraph = currentBlock.kind == TextParagraph and
                    not currentBlock.text.isEmptyOrWhitespace()

        # TODO: fix all strings having a trailing newline
        if not isEmptyLine:
            currentBlock.text &= line & "\n"

        if isEmptyLine and isClosingParagraph:
            result.add(currentBlock)
            currentBlock = createDefaultBlock()
        elif isEmptyLine and currentBlock.kind == Blockquote:
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
        elif line.match(RegexStartOfList):
            currentBlock.kind = List
        elif line.startsWith("|"):
            currentBlock.kind = Table

        if isEmptyLine:
            let isClosingBlock = currentBlock.kind in @[List, Html, Table] or (
                    currentBlock.kind == GDQuestShortcode and
                    previousLine.strip().endsWith("%}"))
            if isClosingBlock:
                result.add(currentBlock)
                currentBlock = createDefaultBlock()

            currentBlock.kind = EmptyLine
            currentBlock.text = "\n"
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
        let content = readFile(file)
        let formattedContent = formatContent(content)
        if args.inPlace:
            writeFile(file, formattedContent)
        else:
            echo formattedContent
            assert formattedContent == content, "Formatted content doesn't match original content:\n\n" & content
            #var outputFile = args.outputDirectory / file.lastPathPart()
            #writeFile(outputFile, formattedContent)
