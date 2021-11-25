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
import re


type
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

proc parseCommandLineArguments(): tuple =
    var inputFiles: seq[string] = @[]
    return (
        files: inputFiles,
        inPlace: false,
        outputDirectory: ".",
    )

# Takes a sequence of blocks from a parsed markdown file and outputs a formatted document.
proc convertBlocksToFormattedMarkdown(blocks: seq[Block]): string =
    const IgnoredBlockKinds = [EmptyLine, YamlFrontMatter, Blockquote, Heading, Table, GDQuestShortcode, Reference]
    for mdBlock in blocks:
        case mdBlock.kind:
            of IgnoredBlockKinds:
                result &= mdBlock.text
            of CodeBlock:
                #TODO: code block formatting
                continue
            else:
                #TODO: regular text formatting
                continue
    
proc getFormattedText(): string =
    # Formats to skip: **a**, *a*, _a_, `a`, [a][a] (reference) ![a](a), [a](a)
    return

proc parseBlocks(content: seq[string]): seq[Block] =

    proc createDefaultBlock(): Block =
        return Block(
            kind: TextParagraph,
            text: "",
        )

    var currentBlock = createDefaultBlock()
    var previousLine = ""
    for line in content:

        let
            isEmptyLine = line.strip() == ""
            isClosingParagraph = currentBlock.kind == TextParagraph and
                    previousLine.strip() != ""

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
        elif line.startsWith("{{"):
            if currentBlock.kind == TextParagraph:
                currentBlock.kind = GDQuestShortcode
        elif line.startsWith("["):
            currentBlock.kind = Reference
            currentBlock = createDefaultBlock()

        if currentBlock.kind == GDQuestShortcode and line.strip().endsWith("}}"):
            result.add(currentBlock)
            currentBlock = createDefaultBlock()

        if isEmptyLine:
            currentBlock.kind = EmptyLine
            currentBlock.text = "\n"
            currentBlock = createDefaultBlock()

        previousLine = line

if isMainModule:
    var args = parseCommandLineArguments()
    for file in args.files:
        let content = readFile(file)
        let blocks = parseBlocks(content.splitLines())
        let formattedContent = convertBlocksToFormattedMarkdown(blocks)
        if args.inPlace:
            writeFile(file, formattedContent)
        else:
            var outputFile = args.outputDirectory/ file.lastPathPart()
            writeFile(outputFile, formattedContent)
