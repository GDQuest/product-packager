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

import panflute

LOGGER = logging.getLogger("format_tutorial.py")

ERROR_PROJECT_DIRECTORY_NOT_FOUND: int = 1
ERROR_LINK_TO_NONEXISTENT_FILE: int = 2

project_directory: str = ""


def find_content_files(project_directory: str) -> dict:
    """Maps the name of markdown files in the project to their full path."""
    files: dict = {}
    include_extensions: set = {".md"}

    content_directory = os.path.join(project_directory, "content")

    for dirpath, dirnames, filenames in os.walk(content_directory):
        dirnames = [d for d in dirnames if not d.startswith(".")]
        for filename in filenames:
            if os.path.splitext(filename)[-1].lower() not in include_extensions:
                continue
            files[filename] = {
                "path": os.path.relpath(
                    os.path.join(dirpath, filename), content_directory
                )
            }
    return files


def process_links(elem, doc, files):
    """Pandoc filter to process link patterns with the form
    `{% link FileName %}`

    Directly replaces the content of matched markdown elements."""

    REGEX_LINK: re.Pattern = re.compile(r"{% *link (\w+) *%}")
    LINK_TEMPLATE: str = "[{}](../{})"

    if not type(elem) in [panflute.Str]:
        return

    match: re.Match = REGEX_LINK.match(elem.text)
    if match:
        filename: str = match.group(1)
        if not filename in files:
            LOGGER.error("Trying to link to a nonexistent file, aborting.")
            sys.exit(ERROR_LINK_TO_NONEXISTENT_FILE)
        elem.text = LINK_TEMPLATE.format(filename, filename)


def main(doc=None):
    def find_git_root_directory() -> str:
        """Attempts to find a .git directory, starting to the folder where we run the
    script and moving up the filesystem."""
        out: str = ""
        path = os.getcwd()
        for index in range(5):
            if os.path.exists(os.path.join(path, ".git")):
                out = path
                break
            path = os.path.join(path, "..")
        return os.path.realpath(out)
    project_directory = find_git_root_directory()
    if not project_directory:
        LOGGER.error("Project directory not found, aborting.")
        sys.exit(ERROR_PROJECT_DIRECTORY_NOT_FOUND)

    files = find_content_files(project_directory)
    return panflute.run_filter(process_links, doc=doc, files=files)


if __name__ == "__main__":
    main()
