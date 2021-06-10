"""
Pandoc filter to include the content of files or part of files.

Features:

- Tries to automatically find the file in the given project.
- Include only part of a file delimited with anchors as comments (supports GDScript comments).

Usage syntax:

- {% include FileName.gd %} - finds and includes the complete file.
- {% include FileName.gd anchor_name %} - finds and includes part of the file.
- {% include path/to/FileName.gd anchor_name %} - includes part of the provided file path.
"""

# Finding files:
# DONE: find or get project directory
# DONE: map filenames to file paths in project
# DONE: map anchors to files?
# DONE: mark multiple files with the same name and output warning
#
# Template:
# DONE: parse template arguments
# DONE: distinguish dirpaths from filenames
# DONE: if a filename matches multiple files, error out
# DONE: store anchor
#
# Parsing files
# DONE: find and cache lines inside anchors?
# DONE: remove any line containing an anchor
#
# filter:
# TODO: find and replace the pattern
# DONE: write main function running filter
import os
import re
import sys
from dataclasses import dataclass
from typing import List, Tuple

import panflute

ERROR_PROJECT_DIRECTORY_NOT_FOUND: int = 1
ERROR_ATTEMPT_TO_FIND_DUPLICATE_FILE: int = 2

# Cached for the whole script.
files: dict = {}
duplicate_files: list = []
project_directory: str = ""


@dataclass
class Include:
    """Holds the path, anchor, and text for an include template."""

    file_path: str
    anchor: str
    text: str


def parse_include_template(content: str) -> Include:
    REGEX_INCLUDE: re.Pattern = re.compile(
        r"include [\"']?(?P<file>.+?\.[a-zA-Z0-9]+)[\"']? [\"']?(?P<anchor>\w+)[\"']?"
    )
    match: re.Match = REGEX_INCLUDE.match(content)
    return Include(match.group("file"), match.group("anchor"))


def is_include_line(line: str) -> bool:
    REGEX_INCLUDE_LINE: re.Pattern = re.compile(r"^{% include .+%}$")
    return REGEX_INCLUDE_LINE.match(line) is not None


def is_filename(file_path: str) -> bool:
    """Returns `True` if the provided path does not contain a slash character."""
    return not file_path.find("/") and not file_path.find("\\")


def find_file(project_directory: str, name: str) -> str:
    for dirpath, dirnames, filenames in os.walk(project_directory):
        for filename in filenames:
            if filename == name:
                filepath: str = os.path.join(dirpath, filename)
                yield filepath


def find_project_files(project_directory: str) -> Tuple[dict, list]:
    """Maps the name of files in the project to their full path."""
    files: dict = {}
    duplicate_files: list = []
    include_extensions: set = {".gd"}

    for dirpath, dirnames, filenames in os.walk(project_directory):
        dirnames = [d for d in dirnames if not d.startswith(".")]
        for filename in filenames:
            if os.path.splitext(filename).lower() not in include_extensions:
                continue

            if filename in files:
                duplicate_files.append(filename)
            else:
                files[filename]["path"] = os.path.join(dirpath, filename)
    return files, duplicate_files


def get_file_content(file_path: str) -> str:
    content: str = ""
    if is_filename(file_path):
        assert (
            file_path not in duplicate_files
        ), "The requested file to include has duplicates with the same name in the project."
        file_path = files[file_path]["path"]

    with open(file_path, "r") as text_file:
        content = text_file.read()
    return content


def find_all_file_anchors(content: str) -> dict:
    """Returns a dictionary mapping anchor names to the corresponding lines."""

    def find_all_anchors_in_file(content: str) -> List[str]:
        """Finds and returns the list of all anchors inside `content`."""
        REGEX_ANCHOR_START: re.Pattern = re.compile(
            r"^\s*# ANCHOR: (\w+)\s*$", flags=re.MULTILINE
        )
        return REGEX_ANCHOR_START.findall(content)

    anchor_map: dict = {}
    ANCHOR_REGEX_TEMPLATE = r"^\s*# ANCHOR: {}\s*$(.+)^\s*# END: {}\s*$"

    anchors = find_all_anchors_in_file(content)

    for anchor in anchors:
        regex_anchor: re.Pattern = re.compile(
            ANCHOR_REGEX_TEMPLATE.format(anchor, anchor), flags=re.MULTILINE | re.DOTALL
        )
        match: re.Match = regex_anchor.match(content)
        if not match:
            # TODO: log error
            print('Malformed anchor pattern for anchor "{}"'.format(anchor))
            sys.exit(ERROR_ATTEMPT_TO_FIND_DUPLICATE_FILE)
        anchor_content = re.sub(
            r"^\s*# (ANCHOR|END): \w+\s*$", "", match.group(1), flags=re.MULTILINE
        )
        anchor_map[anchor] = anchor_content
    return anchor_map


def process_includes(elem, doc):
    if not type(elem) == panflute.CodeBlock:
        return

    line: str = elem.text

    include: Include = parse_include_template(line)
    path: str = include.file_path
    content: str = get_file_content(path)

    if "anchors" not in files[path]:
        files[path]["anchors"] = find_all_file_anchors(content)

    anchor_content: str = files[path]["anchors"][include.anchor]
    print(anchor_content)


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
    return out


def main(doc=None):
    # TODO: find Godot directory only?
    project_directory = find_git_root_directory()
    if not project_directory:
        # TODO: replace with logger warning
        print("E")
        sys.exit(ERROR_PROJECT_DIRECTORY_NOT_FOUND)

    files, duplicate_files = find_project_files(project_directory)
    if duplicate_files:
        # TODO: replace with logger warning
        print("Found duplicates in the project: " + str(duplicate_files))

    return panflute.run_filter(process_includes, doc=doc)


if __name__ == "__main__":
    main()
