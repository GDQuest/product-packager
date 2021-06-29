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

LINK_LOGGER = logging.getLogger("format_tutorial.py")

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
            name, extension = os.path.splitext(filename)
            if extension.lower() not in include_extensions:
                continue
            files[name] = {
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

    def is_link_template(element) -> bool:
        return (
            type(element.content[0]) == panflute.Str
            and element.content[0].text == "{%"
            and type(element.content[1]) == panflute.Space
            and type(element.content[2]) == panflute.Str
            and element.content[2].text == "link"
            and type(element.content[3]) == panflute.Space
            and type(element.content[-1]) == panflute.Str
            and element.content[-1].text == "%}"
        )

    if not type(elem) in [panflute.Para]:
        return
    if not is_link_template(elem):
        return

    filename: str = elem.content[4].text
    if not filename in files:
        LINK_LOGGER.error("Trying to link to a nonexistent file named '{}', aborting.".format(filename))
        sys.exit(ERROR_LINK_TO_NONEXISTENT_FILE)
    return panflute.convert_text(LINK_TEMPLATE.format(filename, filename))


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
        LINK_LOGGER.error("Project directory not found, aborting.")
        sys.exit(ERROR_PROJECT_DIRECTORY_NOT_FOUND)

    files = find_content_files(project_directory)
    return panflute.run_filter(process_links, doc=doc, files=files)


if __name__ == "__main__":
    main()
