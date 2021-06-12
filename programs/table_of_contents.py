#!/usr/bin/env python3
"""Replaces a {% contents %} template with a table of contents for the document.
"""

import re
from typing import List
import sys

from dataclasses import dataclass
import logging


LOGGER = logging.getLogger("format_tutorial.py")


@dataclass
class Heading:
    """Helper to create a tree of headings and their anchor."""

    title: str
    anchor: str
    level: int


RE_HEADING: re.Pattern = re.compile(r"^(#+)(.+)$", re.MULTILINE)
RE_TEMPLATE_CONTENTS: re.Pattern = re.compile(r"^{% contents %}$", re.MULTILINE)


def find_headings(text: str) -> List[Heading]:
    heading_lines = RE_HEADING.findall(content)
    out: List[Heading] = []
    for line in heading_lines:
        title: str = line.lstrip("# ")
        anchor: str = title.lower().replace(" ", "-")
        level: int = title.split(" ", 1)[0].count("#")
        out.append(Heading(title, anchor, level))
    return out


def generate_table_of_contents(headings: List[Heading]) -> str:
    out: List[str] = ["Contents:", ""]
    for heading in headings:
        line = "  " * heading.level + "- [{}]({})".format(heading.title, heading.anchor)
        out.append(line)
    return "\n".join(out)


def main():
    output: str = ""

    content: str = ""
    file_path: str = sys.argv[1]
    with open(file_path, "r") as input_file:
        content = input_file.read()
    if content == "":
        LOGGER.error("Could not read file {}. Aborting.".format(file_path))

    match: re.Match = RE_TEMPLATE_CONTENTS.match(content)
    if match:
        headings: List[Heading] = find_headings(content)
        table_of_contents: str = generate_table_of_contents(headings)
        output = content[:match.start()] + table_of_contents + content[match.end():]

    print(output)


if __name__ == "__main__":
    main()
