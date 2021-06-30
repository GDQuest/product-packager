#!/usr/bin/env python3
"""Replaces a {% contents %} template with a table of contents for the document.
"""

import re
from typing import List
import sys

from dataclasses import dataclass
import logging

ERROR_COULD_NOT_OPEN_INPUT_FILE: int = 1

LOGGER = logging.getLogger("format_tutorial.py")


@dataclass
class Heading:
    """Helper to create a tree of headings and their anchor."""

    title: str
    anchor: str
    level: int


RE_HEADING: re.Pattern = re.compile(r"^(#+)(.+)$")
RE_TEMPLATE_CONTENTS: re.Pattern = re.compile(r"^{% contents %}$")
RE_SPLIT_CODE_BLOCK: re.Pattern = re.compile(r"(```[a-z]*.*?```)", flags=re.DOTALL)


def find_headings(text: str) -> List[Heading]:
    out: List[Heading] = []

    blocks = RE_SPLIT_CODE_BLOCK.split(text)
    for block in blocks:
        if block.startswith("```"):
            continue

        lines = block.split("\n")
        heading_lines = [line for line in lines if RE_HEADING.search(line) is not None]
        for line in heading_lines:
            # Skip document title
            if line.startswith("# "):
                continue

            title: str = line.lstrip("# ").rstrip("\n")
            anchor: str = title.lower().replace(" ", "-").replace("'", "").rstrip("?!")
            # Subtract 2 so level-2 headings are unindented
            level: int = line.split(" ", 1)[0].count("#") - 2
            out.append(Heading(title, anchor, level))

    return out


def generate_table_of_contents(
    headings: List[Heading], max_level: int = 3
) -> List[str]:
    out: List[str] = ["Contents:\n", "\n"]
    for heading in headings:
        if heading.level > max_level:
            continue
        line = (
            "  " * heading.level
            + "- [{}](#{})".format(heading.title, heading.anchor)
        )
        out.append(line)
    return out


def replace_contents_template(content: str) -> str:
    """Finds and replace a template with the form {% contents %}"""
    output: List[str] = content.split("\n")

    index = 0
    split_content: List[str] = output
    for line in split_content:
        if line == "{% contents %}":
            headings: List[Heading] = find_headings(content)
            table_of_contents: List[str] = generate_table_of_contents(headings)
            output = split_content[:index] + table_of_contents + split_content[index + 1 :]
            break
        index += 1
    return "\n".join(output)


def get_file_content(file_path: str) ->str:
    output: str = ""
    with open(file_path, "r") as input_file:
        output = input_file.read()
        if not output:
            LOGGER.error("Could not read file {}. Aborting.".format(file_path))
            sys.exit(ERROR_COULD_NOT_OPEN_INPUT_FILE)
    return output


def main():
    file_path: str = sys.argv[1]
    content: str = get_file_content(file_path)
    print(replace_contents_template(content))


if __name__ == "__main__":
    main()
