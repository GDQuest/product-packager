#!/usr/bin/env python3
"""
Pandoc filter to link to another file. Designed for node essentials.

Features:

- Finds the file to link to by name.

Usage syntax:

- {% link FileName %} - finds and includes the complete file.
"""
import logging
import os
import re
import sys

from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

from datargs import arg, parse

LINK_LOGGER = logging.getLogger("link.py")

ERROR_PROJECT_DIRECTORY_NOT_FOUND: int = 1
ERROR_LINK_TO_NONEXISTENT_FILE: int = 2


@dataclass
class Args:
    input_file: Path = arg(
        positional=True, help="A single markdown file to process for include templates."
    )


def find_content_files(project_directory: str) -> dict:
    """Maps the name of markdown files in the project to their full path."""
    files: dict = {}
    include_extensions: set = {".md"}

    content_directory = os.path.join(project_directory, "content")

    for dirpath, dirnames, filenames in os.walk(content_directory):
        dirnames = [d for d in dirnames if not d.startswith(".")]
        for filename in filenames:
            name, extension = os.path.splitext(filename)
            if extension.lower() not in include_extensions:
                continue
            files[name] = {
                "path": os.path.relpath(
                    os.path.join(dirpath, filename), content_directory
                )
            }
    return files


def replace_links(content: str, files: List[Path]):
    """Pandoc filter to process link patterns with the form
    `{% link FileName %}`

    Directly replaces the content of matched markdown elements."""

    LINK_TEMPLATE: str = "[{}](../{})"
    REGEX_LINK: re.Pattern = re.compile(r"{% *link (\w+) *%}")

    def replace_link(match: re.Match) -> str:
        filename: str = match.group(1)
        if not filename in files:
            LINK_LOGGER.error(
                "Trying to link to a nonexistent file named '{}', aborting.".format(
                    filename
                )
            )
            sys.exit(ERROR_LINK_TO_NONEXISTENT_FILE)
        return LINK_TEMPLATE.format(filename, filename)

    return REGEX_LINK.sub(replace_link, content)


def find_git_root_directory(file_path: Path) -> Path:
    """Attempts to find a .git directory, starting to the folder where we run the
    script and moving up the filesystem."""
    path: Path = file_path.parent
    for index in range(5):
        if Path(path, ".git").exists():
            out = path
            break
        path = path.parent
    return path


def process_document(file_path: Path) -> str:
    output: str = ""
    project_directory: Path = find_git_root_directory(file_path)
    if not project_directory:
        LINK_LOGGER.error("Error: no documents to link to found. Aborting.")
        sys.exit(ERROR_PROJECT_DIRECTORY_NOT_FOUND)

    files = find_content_files(project_directory)
    if not files:
        LINK_LOGGER.warning(
            "Warning: no project documents found, links will need to use complete paths to the target."
        )

    with open(file_path, "r") as input_file:
        content: str = input_file.read()
        output = replace_links(content)

    return output


def main():
    args: Args = parse(Args)
    if not args.input_file.exists():
        LINK_LOGGER.error(
            "File {} not found. Aborting operation.".format(args.input_file.as_posix())
        )
    output = process_document(args.input_file)
    print(output)


if __name__ == "__main__":
    main()
