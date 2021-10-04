#!/usr/bin/env python3
"""
Auto-formats our tutorials, saving manual formatting work:

- Converts space-based indentations to tabs in code blocks.
- Fills GDScript code comments as paragraphs.
- Wraps symbols and numeric values in code.
- Wraps other capitalized names, pascal case values into italics (we assume they're node names).
- Marks code blocks without a language as using `gdscript`.
- Add <kbd> tags around keyboard shortcuts (the form needs to be Ctrl+F1).
"""
import argparse
import itertools
import logging
import os
import re
import sys
import textwrap
from dataclasses import dataclass
from typing import List

import colorama
from lib.gdscript_classes import BUILT_IN_CLASSES

TAB_WIDTH: int = 4

LOGGER = logging.getLogger("format_tutorial.py")

ERROR_PYTHON_VERSION_TOO_OLD: int = 1
ERROR_INCORRECT_FILE_PATHS: int = 2

WORDS_TO_KEEP_UNFORMATTED: List[str] = [
    "gdquest",
    "gdscript",
    "godot",
    "stack overflow",
    "google",
    "youtube",
    "twitter",
    "facebook",
    "discord",
    "instagram",
    "duckduckgo",
]

RE_SPLIT_CODE_BLOCK: re.Pattern = re.compile(r"(```[a-z]*.*?```)", flags=re.DOTALL)
RE_SPLIT_HTML: re.Pattern = re.compile(r"(<.+?>.*?<\/.+?>)", flags=re.DOTALL)
RE_SPLIT_TEMPLATE: re.Pattern = re.compile(r"({%.+?%})")
RE_SPLIT_FRONT_MATTER: re.Pattern = re.compile(r"(---.+?---\n)", flags=re.DOTALL)
RE_BUILT_IN_CLASSES: re.Pattern = re.compile(
    r"\b(?<!`)({})\b".format(r"|".join(BUILT_IN_CLASSES))
)
# Matches paths with a filename at the end.
PATTERN_DIR_PATH: str = r"\b((res|user)://)?/?(([\w]+/)+(\w*\.\w+)?\b)"
PATTERN_FILE_AT_ROOT: str = r"(res|user)://\w+\.\w+"
SUPPORTED_EXTENSIONS: List[str] = [
    "png",
    "jpe?g",
    "mp4",
    "mkv",
    "t?res",
    "t?scn",
    "gd",
    "py",
    "shader",
]
PATTERN_FILENAME_ONLY: str = r"(\w+\.({}))".format("|".join(SUPPORTED_EXTENSIONS))
RE_FILE_PATH: re.Pattern = re.compile(
    "|".join([PATTERN_DIR_PATH, PATTERN_FILE_AT_ROOT, PATTERN_FILENAME_ONLY])
)
# Matches directory paths without a filename at the end. Group 1 targets the path.
#
# Known limitations:
# - The path requires a trailing slash followed by a space, or period and space,
# or the line ends with a period.
# - Won't capture a leading slash.
SINGLE_FUNCTION_CALL: str = r"\b_?\w+(\.\w+)*\([\"'_a-zA-Z0-9, ]*\)"
SINGLE_VARIABLE: str = r"\b_\w+|\b[a-zA-Z0-9]+_\w+"
VARIABLE_AND_PROPERTY = r"\b_?\w+\.\w+"
RE_VARIABLE_OR_FUNCTION: re.Pattern = re.compile(
    "|".join([SINGLE_FUNCTION_CALL, SINGLE_VARIABLE, VARIABLE_AND_PROPERTY])
)
RE_NUMERIC_VALUES_AND_RANGES: re.Pattern = re.compile(
    r"(\d+x\d+)|(\[[\d\., ]+\])|(-?\d+\.\d+)|(?<![\nA-Za-z])(-?\d+)(?![A-Za-z])(?!\. )"
)
# Sequence of multiple words with an optional "->" separator, to italicize.
RE_TO_ITALICIZE_SEQUENCE: re.Pattern = re.compile(
    r"(?<![\-\.] )(?<!^)[A-Z0-9]+[a-zA-Z0-9]*( (-> )?[A-Z][a-zA-Z0-9]+(\.\.\.)?)+",
    flags=re.MULTILINE,
)
# Capitalized words and PascalCase that are not at the start of a sentence or a line.
RE_TO_ITALICIZE_ONE_WORD: re.Pattern = re.compile(
    r"^([A-Z]\w+[A-Z]\w+)|(?<![\.\-:;?!] )(?<!^)([A-Z][a-zA-Z0-9]+(\.\.\.)?)",
    flags=re.MULTILINE,
)
RE_TO_IGNORE: re.Pattern = re.compile(r"(!?\[.*\]\(.+\)|^#+ .+$)", flags=re.MULTILINE)
RE_KEYBOARD_SHORTCUTS: re.Pattern = re.compile(
    r"(?<!\d\. ) +((Ctrl|Alt|Shift|CTRL|ALT|SHIFT) ?\+ ?)(F\d{1,2}|[A-Z0-9])"
)
RE_KEYBOARD_SHORTCUTS_ONE_ELEMENT: re.Pattern = re.compile(
    r"Ctrl|Alt|Shift|CTRL|ALT|SHIFT|[A-Z0-9]+"
)
RE_HEX_VALUES: re.Pattern = re.compile(r"#[a-fA-F0-9]{3,8}")
RE_INSIDE_DOUBLE_QUOTES: re.Pattern = re.compile(r'[^\w]("[^"]*")[^\w]')
RE_INSIDE_SINGLE_QUOTES: re.Pattern = re.compile(r"[^\w]('[^']*')[^\w]")
RE_MARKDOWN_BLOCKQUOTE: re.Pattern = re.compile(r"^(> )(.+?)$", flags=re.MULTILINE)


@dataclass
class ProcessedDocument:
    """Maps a file path to formatted content"""

    file_path: str
    content: str


def inline_code_built_in_classes(text: str) -> str:
    return RE_BUILT_IN_CLASSES.sub(lambda match: "`{}`".format(match.group(0)), text)


def inline_code_paths(text: str) -> str:
    return RE_FILE_PATH.sub(lambda match: "`{}`".format(match.group(0)), text)


def inline_code_variables_and_functions(text: str) -> str:
    return RE_VARIABLE_OR_FUNCTION.sub(
        lambda match: "`{}`".format(match.group(0)), text
    )


def inline_code_hex_values(text: str) -> str:
    return RE_HEX_VALUES.sub(lambda match: "`{}`".format(match.group(0)), text)


def inline_code_numeric_values(text: str) -> str:
    return RE_NUMERIC_VALUES_AND_RANGES.sub(
        lambda match: "`{}`".format(match.group(0)),
        text,
    )


def replace_double_inline_code_marks(text: str) -> str:
    """Finds and replaces cases where we have `` to `."""
    return re.sub("(`+\b)|(\b`+)", "`", text)


def italicize_word_sequences(text: str) -> str:
    return RE_TO_ITALICIZE_SEQUENCE.sub(
        lambda match: "*{}*".format(match.group(0)), text
    )


def italicize_other_words(text: str) -> str:
    def replace_match(match: re.Match) -> str:
        expression: str = match.group(0)
        if (
            expression.lower() in WORDS_TO_KEEP_UNFORMATTED
            or expression.upper() == expression
        ):
            return expression
        return "*{}*".format(match.group(0))

    return RE_TO_ITALICIZE_ONE_WORD.sub(replace_match, text)


def add_keyboard_tags(text: str) -> str:
    def add_one_keyboard_tag(match: re.Match) -> str:
        expression = match.group(0)
        if expression.strip() == "I":
            return expression
        return RE_KEYBOARD_SHORTCUTS_ONE_ELEMENT.sub(
            lambda m: "<kbd>{}</kbd>".format(m.group(0)),
            expression,
        )

    return RE_KEYBOARD_SHORTCUTS.sub(add_one_keyboard_tag, text)


FORMATTERS = [
    inline_code_paths,
    inline_code_variables_and_functions,
    italicize_word_sequences,
    add_keyboard_tags,
    inline_code_built_in_classes,
    inline_code_hex_values,
    italicize_other_words,
    inline_code_numeric_values,
]


def format_line(line: str) -> str:
    def split_formatted_words(text: str) -> List[str]:
        return [s for s in re.split(r"([`*].+?[`*])", text) if s != ""]

    out: str = line
    split_line: List[str] = split_formatted_words(line)

    if len(split_line) > 1:
        out = "".join(list(map(format_line, split_line)))

    elif not re.match("^[`*]", line):
        for formatter in FORMATTERS:
            formatted_line: str = formatter(line)
            if formatted_line == line:
                continue

            split_line: List[str] = split_formatted_words(formatted_line)
            if len(split_line) > 1:
                out = "".join(list(map(format_line, split_line)))
            else:
                out = formatted_line
            break
    return out


def format_content(content: str) -> str:
    """Applies styling rules to content other than a code block."""
    return "\n".join(list(map(format_line, content.split("\n"))))


def format_code_block(text: str):
    """Applies styling rules to one code block"""

    def convert_spaces_to_tabs(content: str) -> str:
        return content.replace(" " * TAB_WIDTH, "\t")

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

    match = re.match("```([a-z]+)?\n(.*?)```", text, flags=re.DOTALL)

    language = match.group(1) or "gdscript"

    content = match.group(2)
    content = convert_spaces_to_tabs(content)
    content = re.sub("\t*#.+", fill_comment, content, flags=re.MULTILINE)

    output = "```{}\n{}```".format(language, content)
    return output


def parse_command_line_arguments(args) -> argparse.Namespace:
    """Parses the command line arguments"""
    parser = argparse.ArgumentParser(
        description=__doc__,
    )
    parser.add_argument(
        "files",
        type=str,
        nargs="+",
        default="",
        help="A list of paths to markdown files.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="",
        help="Path to the output directory.",
    )
    parser.add_argument(
        "-i", "--in-place", action="store_true", help="Overwrite the source files."
    )
    return parser.parse_args(args)


def process_content(content: str) -> str:
    """Applies formatting rule to a file's content."""

    def flatten(items):
        for item in items:
            if isinstance(item, list) and not isinstance(item, (str, bytes)):
                yield from flatten(item)
            else:
                yield item

    def is_code_block(text: str) -> bool:
        return text.startswith("```")

    def is_unformatted_block(text: str) -> bool:
        """Returns true if the text starts like HTML, a template element, a
        blockquote, or a quote symbol."""
        ignore_pairs = [
            ("```", "```"),
            ("<", ">"),
            ("---", "---"),
            ("{%", "%}"),
            ("'", "'"),
            ('"', '"'),
        ]
        for opening, closing in ignore_pairs:
            if text.lstrip().startswith(opening) and text.rstrip().endswith(closing):
                return True
        return False

    def split_by_regex(text: str, regex: str) -> List[str]:
        if is_unformatted_block(text):
            return [text]
        return re.split(regex, text)

    sections = RE_SPLIT_CODE_BLOCK.split(content)
    for regex in [
        RE_SPLIT_FRONT_MATTER,
        RE_SPLIT_HTML,
        RE_SPLIT_TEMPLATE,
        RE_INSIDE_DOUBLE_QUOTES,
        RE_INSIDE_SINGLE_QUOTES,
        RE_MARKDOWN_BLOCKQUOTE,
    ]:
        sections = map(split_by_regex, sections, itertools.repeat(regex))
        sections = list(flatten(sections))
    sections = list(filter(lambda text: bool(text), sections))

    formatted_sections: List[str] = []

    for block in sections:
        if is_code_block(block):
            formatted_sections.append(format_code_block(block))
        elif is_unformatted_block(block):
            formatted_sections.append(block)
        else:
            chunks: List[str] = re.split(RE_TO_IGNORE, block)
            formatted_chunks: List[str] = []
            for chunk in chunks:
                if re.match(RE_TO_IGNORE, chunk):
                    formatted_chunks.append(chunk)
                else:
                    formatted_chunks.append(format_content(chunk))
            formatted_sections.append("".join(formatted_chunks))

    return "".join(formatted_sections)


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


def print_error(*args, **kwargs):
    print(colorama.Fore.RED, end="", flush=True)
    print(*args, file=sys.stderr, **kwargs)
    print(colorama.Fore.RESET, end="", flush=True)


def main():
    def is_python_version_compatible() -> bool:
        return sys.version_info.major == 3 and sys.version_info.minor >= 8

    args: argparse.Namespace = parse_command_line_arguments(sys.argv[1:])
    logging.basicConfig(level=logging.ERROR)
    if not is_python_version_compatible():
        print_error(
            "\n".join(
                [
                    "Your Python version ({}.{}.{}) is too old.",
                    "Minimum required version: 3.8.",
                    "Please install a more recent Python version.",
                    "Aborting operation.",
                ]
            ).format(
                sys.version_info.major, sys.version_info.minor, sys.version_info.micro
            )
        )
        sys.exit(ERROR_PYTHON_VERSION_TOO_OLD)

    filepaths: List[str] = [
        f for f in args.files if f.lower().endswith(".md") and os.path.exists(f)
    ]
    if len(filepaths) != len(args.files):
        print_error(
            "\n".join(
                [
                    "Some files are missing or their path is incorrect.",
                    "Please ensure there's no typo in the path.",
                    "Aborting operation.",
                ]
            )
        )
        sys.exit(ERROR_INCORRECT_FILE_PATHS)

    documents: List[ProcessedDocument] = []
    for file_path in filepaths:
        with open(file_path, "r") as markdown_file:
            content: str = markdown_file.read()
            documents.append(ProcessedDocument(file_path, process_content(content)))
    list(map(output_result, itertools.repeat(args), documents))


if __name__ == "__main__":
    main()
