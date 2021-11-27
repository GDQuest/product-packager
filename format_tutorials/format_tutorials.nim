# Auto-formats our tutorials, saving manual formatting work:
# 
# - Converts space-based indentations to tabs in code blocks.
# - Fills GDScript code comments as paragraphs.
# - Wraps symbols and numeric values in code.
# - Wraps other capitalized names, pascal case values into italics (we assume they're node names).
# - Marks code blocks without a language as using `gdscript`.
# - Add <kbd> tags around keyboard shortcuts (the form needs to be Ctrl+F1).

import os
import strutils
import parseopt
import re


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
        GDQuestShortcode

    Block = ref object
        kind: BlockKind
        text: string


proc getFormattedText(text: string): string =
    # Formats to skip: **a**, *a*, _a_, `a`, [a][a] (reference) ![a](a), [a](a)
    result = ""


proc getFormattedCodeBlock(text: string): string =
    let lines = text.splitLines()
    result &= (if lines[0].strip() == "```": "```gdscript" else: lines[0])
    for line in lines[1 .. ^1]:
        if not line.match(re"\s*#"):
            result &= line
            continue

        const TabWidth = 4
        var indentLevel = 0
        for character in line:
            if character notin @[' ', '\t']: break
            indentLevel += 1
        if line[0] == '\t':
            indentLevel *= TabWidth

        # TODO: wrap comments at 80 characters
        result &= line


# Takes a sequence of blocks from a parsed markdown file and outputs a formatted document.
proc convertBlocksToFormattedMarkdown(blocks: seq[Block]): string =
    const IgnoredBlockKinds = [EmptyLine, YamlFrontMatter, Blockquote, Heading,
            Table, GDQuestShortcode, Reference]
    for mdBlock in blocks:
        case mdBlock.kind:
            of IgnoredBlockKinds:
                result &= mdBlock.text
            of CodeBlock:
                result &= getFormattedCodeBlock(mdBlock.text)
            else:
                result &= getFormattedText(mdBlock.text)


proc parseBlocks(content: seq[string]): seq[Block] =

    proc createDefaultBlock(): Block =
        return Block(
            kind: TextParagraph,
            text: "",
        )

    let regexListStart = re"- |\d+\. "

    var currentBlock = createDefaultBlock()
    var previousLine = ""
    for line in content:
        let
            isEmptyLine = line.strip() == ""
            isClosingParagraph = currentBlock.kind == TextParagraph and
                    not currentBlock.text.isEmptyOrWhitespace()

        if not isEmptyLine:
            currentBlock.text &= line

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
        elif line.startsWith("{%"):
            if currentBlock.kind == TextParagraph:
                currentBlock.kind = GDQuestShortcode
        elif line.startsWith("["):
            currentBlock.kind = Reference
            currentBlock = createDefaultBlock()
        elif line.match(regexListStart):
            currentBlock.kind = List

        if currentBlock.kind == List and isEmptyLine:
            result.add(currentBlock)
            currentBlock = createDefaultBlock()

        if currentBlock.kind == GDQuestShortcode and line.strip().endsWith("%}"):
            result.add(currentBlock)
            currentBlock = createDefaultBlock()

        if isEmptyLine:
            currentBlock.kind = EmptyLine
            currentBlock.text = "\n"
            result.add(currentBlock)
            currentBlock = createDefaultBlock()

        previousLine = line


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


if isMainModule:
    var args = parseCommandLineArguments()
    for file in args.inputFiles:
        let content = readFile(file)
        let blocks = parseBlocks(content.splitLines())
        for b in blocks:
            echo b.kind
        quit()

        let formattedContent = convertBlocksToFormattedMarkdown(blocks)
        if args.inPlace:
            writeFile(file, formattedContent)
        else:
            var outputFile = args.outputDirectory / file.lastPathPart()
            writeFile(outputFile, formattedContent)
