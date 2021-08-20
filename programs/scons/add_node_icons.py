#!/usr/bin/env python3
"""Markdown preprocessor that reads a markdown document looking for Godot's
built-in class names and appends the corresponding icon image in front.

It only adds icons to built-in node names outside code fences."""
import argparse
import itertools
import logging
import os
import re
import sys
from dataclasses import dataclass
from typing import List

from gdscript_class_list import BUILT_IN_CLASSES
from scons_helper import print_error

LOGGER = logging.getLogger("format_tutorial.py")
ERROR_INCORRECT_FILE_PATHS: int = 2

RE_SPLIT_CODE_BLOCK: re.Pattern = re.compile("(```[a-z]*\n.*?```)", flags=re.DOTALL)
RE_BUILT_IN_CLASSES: re.Pattern = re.compile(
    "(`{}`)".format("`|`".join(BUILT_IN_CLASSES))
)
RE_PASCAL_TO_SNAKE_CASE: re.Pattern = re.compile(
    "((?<=[a-z])[A-Z0-9]|(?!^)[A-Z](?=[a-z]))"
)


@dataclass
class ProcessedDocument:
    """Maps a file path to formatted content"""

    file_path: str
    content: str


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


def process_file(file_path) -> ProcessedDocument:
    output: ProcessedDocument
    with open(file_path, "r") as markdown_file:
        content: str = add_built_in_icons(markdown_file.read())
        output = ProcessedDocument(file_path, content)
    return output


def add_built_in_icons(content: str) -> str:
    """Inserts icons in front of built-in classes outside markdown code fences."""

    def prepend_icon(match: re.Match) -> str:
        """Returns the matched node name pattern as a string, with an image tag for the
        corresponding icon.
        """
        TEMPLATE = '<img src="{}" class="node-icon"/>'
        class_name: str = match.group(0).replace("`", "")

        icon_filename: str = "icon_" + RE_PASCAL_TO_SNAKE_CASE.sub(
            r"_\1", class_name
        ).lower()

        icon_filepath: str = os.path.join(
            os.path.dirname(__file__), "godot-icons", icon_filename + ".svg"
        )
        if not os.path.exists(icon_filepath):
            LOGGER.warning("File {} not found.".format(icon_filepath))
            return match.group(0)

        return TEMPLATE.format(icon_filepath) + match.group(0)

    output: str = ""
    sections: List[str] = re.split(RE_SPLIT_CODE_BLOCK, content)
    formatted_sections: List[str] = []

    for section in sections:
        # Only add image tags outside code fences.
        if not section.startswith("```"):
            section = re.sub(RE_BUILT_IN_CLASSES, prepend_icon, section)
        formatted_sections.append(section)

    return "\n".join(formatted_sections)


def main():
    args: argparse.Namespace = parse_command_line_arguments(sys.argv[1:])
    logging.basicConfig(level=logging.ERROR)
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

    documents: List[ProcessedDocument] = list(map(process_file, filepaths))
    list(map(output_result, itertools.repeat(args), documents))


if __name__ == "__main__":
    main()
