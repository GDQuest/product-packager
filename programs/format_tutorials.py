#!/usr/bin/env python3
"""
Auto-formats our tutorials, saving a bit of work:

- Converts space-based indentations to tabs in code blocks.
- Fills comments as paragraphs.
- Wraps symbols and numeric values in code and italics.
- Wraps other PascalCase values into italics (we assume they're node names).
- Marks code blocks without a language as using `gdscript`.
"""
import argparse
import itertools
import os
import re
import sys
import textwrap
from dataclasses import dataclass
from typing import List

from lib.gdscript_classes import BUILT_IN_CLASSES

TAB_WIDTH: int = 4

RE_SPLIT_CODE_BLOCK: re.Pattern = re.compile("(```[a-z]*\n.*?```)", flags=re.DOTALL)
RE_BUILT_IN_CLASSES: re.Pattern = re.compile("({})".format("|".join(BUILT_IN_CLASSES)))
# Matches paths with a filename at the end.
RE_FILE_PATH: re.Pattern = re.compile(r"\b(res|user)?(://)?/?([\w]+/)*([\w]*\.\w+)\b")
# Matches directory paths without a filename at the end. Group 1 targets the path.
#
# Known limitations:
# - The path requires a trailing slash followed by a space, or period and space,
# or the line ends with a period.
# - Won't capture a leading slash.
RE_DIRECTORY_PATH: re.Pattern = re.compile(
    r"\b(((res|user)(://)|/)?([\w]+/)+)(\.? |\.$)"
)
RE_VARIABLE_OR_FUNCTION: re.Pattern = re.compile(r"\b(_?[a-zA-Z]+(_[a-zA-Z()]+)+)|(_[a-zA-Z()]+)")
RE_NUMERIC_VALUES_AND_RANGES: re.Pattern = re.compile(r"(\[[\d\., ]+\])|\b(\d+\.?\d*)")


@dataclass
class ProcessedDocument:
    """Maps a file path to formatted content"""

    file_path: str
    content: str


def format_content(text: str) -> str:
    """Applies styling rules to content other than a code block."""

    def add_inline_code_to_built_in_classes(text: str) -> str:
        return re.sub(
            RE_BUILT_IN_CLASSES, lambda match: "`{}`".format(match.group(0)), text
        )

    def add_inline_code_to_paths(text: str) -> str:
        text = re.sub(RE_FILE_PATH, lambda match: "`{}`".format(match.group(0)), text)
        # Group 1 of `RE_DIRECTORY_PATH` is what captures the actual path.
        return re.sub(
            RE_DIRECTORY_PATH, lambda match: "`{}`".format(match.group(1)), text
        )

    def add_inline_code_to_variables_and_functions(text: str) -> str:
        return re.sub(RE_VARIABLE_OR_FUNCTION, lambda match: "`{}`".format(match.group(0)), text)

    def add_inline_code_to_numbers(text: str) -> str:
        return re.sub(RE_NUMERIC_VALUES_AND_RANGES, lambda match: "`{}`".format(match.group(0)), text)

    def replace_double_inline_code_marks(text: str) -> str:
        """Finds and replaces cases where we have `` to `."""
        return re.sub("(``\b)|(\b``)", "`", text)

    # TODO: Add italics around other names? Node names, etc.
    output: str = add_inline_code_to_built_in_classes(text)
    output = add_inline_code_to_paths(output)
    output = add_inline_code_to_variables_and_functions(output)
    output = add_inline_code_to_numbers(output)
    output = replace_double_inline_code_marks(output)
    print(output)
    sys.exit()
    return output


def format_code_block(text: str):
    """Applies styling rules to one code block"""

    def convert_spaces_to_tabs(content: str) -> str:
        return re.sub(", " * TAB_WIDTH, "\t", content)

    def fill_comment(match: re.Match, line_length: int = 80) -> str:
        """Takes one line of comment and wraps it at the `line_length` column."""

        def count_indents(text: str) -> int:
            count = 0
            while text[count] == "\t":
                count += 1
            return count

        text = match.group(0)
        indent_level = count_indents(text)
        # We need to pad every line with that many indents, comment signs, and one space.
        # So we take it into account before wrapping
        dash_count = text.count("#", indent_level, indent_level + 2)
        prefix_width = TAB_WIDTH * indent_level + dash_count + 1
        wrap_length = line_length - prefix_width

        trimmed_text = text.lstrip("\t# ")

        wrapped_text = textwrap.wrap(trimmed_text, wrap_length)
        output = [
            "\t" * indent_level + "#" * dash_count + " " + line for line in wrapped_text
        ]
        return "\n".join(output)

    match = re.match("```([a-z]*)\n(.*?)```", text, flags=re.DOTALL)

    language = match.group(1) or "gdscript"

    content = match.group(2)
    content = convert_spaces_to_tabs(content)
    content = re.sub("^#.+", fill_comment, content, flags=re.MULTILINE)

    output = "```{}\n{}```".format(language, content)
    return output


def parse_command_line_arguments(args) -> argparse.Namespace:
    """Parses the command line arguments"""
    parser = argparse.ArgumentParser(description=__doc__,)
    parser.add_argument(
        "files",
        type=str,
        nargs="+",
        default="",
        help="A list of paths to markdown files.",
    )
    parser.add_argument(
        "-o", "--output", type=str, default="", help="Path to the output directory.",
    )
    parser.add_argument(
        "-i", "--in-place", action="store_true", help="Overwrite the source files."
    )
    return parser.parse_args(args)


def process_file(file_path: List[str]) -> ProcessedDocument:
    """Applies formatting rule to a file's content."""
    output: ProcessedDocument

    with open(file_path, "r") as markdown_file:
        content: str = markdown_file.read()
        sections: List[str] = re.split(RE_SPLIT_CODE_BLOCK, content)
        formatted_sections: List[str] = []

        for block in sections:
            if block.startswith("```"):
                formatted_sections.append(format_code_block(block))
            else:
                formatted_sections.append(format_content(block))

        output = ProcessedDocument(file_path, "\n".join(formatted_sections))

    return output


def output_result(args: argparse.Namespace, document: ProcessedDocument) -> None:
    """Outputs the content of each processed document either to:

    - The input file if the program was called with the `--in-place` option.
    - A new file if the program was called with the `--output` option.
    - Otherwise, to the standard output.

    """
    if args.in_place:
        with open(document.file_path, "w") as output_file:
            output_file.write(document.content)
    elif args.output == "":
        print(document.content)
    else:
        output_path = os.path.join(args.output, os.path.basename(document.file_path))
        if not os.path.isdir(args.output):
            os.makedirs(args.output)
        with open(output_path, "w") as output_file:
            output_file.write(document.content)


def main():
    args: argparse.Namespace = parse_command_line_arguments(sys.argv)
    filepaths: List[str] = [f for f in args.files if f.lower().endswith(".md")]
    documents: List[ProcessedDocument] = list(map(process_file, filepaths))
    list(map(output_result, itertools.repeat(args), documents))


if __name__ == "__main__":
    main()
