#!/usr/bin/env python3
"""
Pandoc filter to include the content of files or part of files.

Features:

- Tries to automatically find the file in the given project.
- Include only part of a file delimited with anchors as comments (supports GDScript comments).

Usage syntax:

- {% include FileName.gd %} - finds and includes the complete file.
- {% include FileName.gd anchor_name %} - finds and includes part of the file.
- {% include path/to/FileName.gd anchor_name %} - includes part of the provided file path.

Known limitations:

- Currently, we only automatically find and cache gdscript files in the project.
- Only automatically finds files to include inside the current project, in top-level directories that are Godot projects.
"""
import logging
import os
import re
import sys
from dataclasses import dataclass
from typing import List, Tuple

import panflute

LOGGER = logging.getLogger("include")

ERROR_PROJECT_DIRECTORY_NOT_FOUND: int = 1
ERROR_ATTEMPT_TO_FIND_DUPLICATE_FILE: int = 2

# The variables below are cached for the whole script.
# Maps file names to the path to a found file on the disk.
project_directory: str = ""


@dataclass
class Include:
    """Holds the path, anchor, and text for an include template."""

    file_path: str
    anchor: str
    text: str = ""


def find_godot_project_files(project_directory: str) -> Tuple[dict, list]:
    """Maps the name of files in the project to their full path."""
    files: dict = {}
    duplicate_files: list = []
    include_extensions: set = {".gd", ".shader"}

    godot_directories: List[str] = list(filter(
        lambda name: os.path.isdir(os.path.join(project_directory, name)) and "godot" in name,
        os.listdir(project_directory),
    ))

    for directory_name in godot_directories:
        godot_directory = os.path.join(project_directory, directory_name)

        for dirpath, dirnames, filenames in os.walk(godot_directory):
            dirnames = [d for d in dirnames if not d.startswith(".")]
            for filename in filenames:
                if os.path.splitext(filename)[-1].lower() not in include_extensions:
                    continue

                if filename in files:
                    duplicate_files.append(filename)
                else:
                    files[filename] = {
                       "path": os.path.join(dirpath, filename)
                    }
    return files, duplicate_files


def get_file_content(file_path: str, files: dict, duplicate_files: list) -> str:
    """Returns the content of a file, finding it if `file_path` is only a file name."""

    def is_filename(file_path: str) -> bool:
        """Returns `True` if the provided path does not contain a slash character."""
        return file_path.find("/") == -1 and file_path.find("\\") == -1

    content: str = ""
    if is_filename(file_path):
        assert (
            file_path not in duplicate_files
        ), "The requested file to include has duplicates with the same name in the project."
        file_path = files[file_path]["path"]
    else:
        assert os.path.exists(file_path), "File not found: {}".format(file_path)

    with open(file_path, "r") as text_file:
        content = text_file.read()
    return content


def find_all_file_anchors(content: str) -> dict:
    """Returns a dictionary mapping anchor names to the corresponding lines."""

    def find_all_anchors_in_file(content: str) -> List[str]:
        """Finds and returns the list of all anchors inside `content`."""
        REGEX_ANCHOR_START: re.Pattern = re.compile(
            r"^\s*# *ANCHOR: *(\w+)\s*$", flags=re.MULTILINE
        )
        return REGEX_ANCHOR_START.findall(content)

    anchor_map: dict = {}
    ANCHOR_REGEX_TEMPLATE = r"^\s*# *ANCHOR: *{}\s*$(.+)^\s*# *END: *{}\s*$"

    anchors = find_all_anchors_in_file(content)

    for anchor in anchors:
        regex_anchor: re.Pattern = re.compile(
            ANCHOR_REGEX_TEMPLATE.format(anchor, anchor), flags=re.MULTILINE | re.DOTALL
        )
        match: re.Match = regex_anchor.match(content)
        if not match:
            LOGGER.error('Malformed anchor pattern for anchor "{}"'.format(anchor))
            sys.exit(ERROR_ATTEMPT_TO_FIND_DUPLICATE_FILE)
        anchor_content = re.sub(
            r"^\s*# (ANCHOR|END): \w+\s*$", "", match.group(1), flags=re.MULTILINE
        )
        anchor_map[anchor] = anchor_content
    return anchor_map


def process_includes(elem, doc, files, duplicate_files):
    """Pandoc filter to process include patterns with the form
    `{% include FileName anchor_name %}`

    Directly replaces the content of matched markdown elements."""

    REGEX_INCLUDE_LINE: re.Pattern = re.compile(r"^{% include .+%}$", re.MULTILINE)

    def parse_include_template(content: str) -> Include:
        REGEX_INCLUDE: re.Pattern = re.compile(
            r"{% *include [\"']?(?P<file>.+?\.[a-zA-Z0-9]+)[\"']? [\"']?(?P<anchor>\w+)[\"']? *%}"
        )
        match: re.Match = REGEX_INCLUDE.match(content)
        assert match.group("file") and match.group(
            "anchor"
        ), "Missing file or anchor in the include template."
        return Include(match.group("file"), match.group("anchor"))

    def contains_include_pattern(line: str) -> bool:
        return REGEX_INCLUDE_LINE.match(line) is not None

    if not type(elem) in [panflute.CodeBlock]:
        return
    if not contains_include_pattern(elem.text):
        return

    line: str = elem.text
    include: Include = parse_include_template(line)
    path: str = include.file_path
    content: str = get_file_content(path, files, duplicate_files)

    if "anchors" not in files[path]:
        files[path]["anchors"] = find_all_file_anchors(content)

    anchor_content: str = files[path]["anchors"][include.anchor]
    elem.text = anchor_content


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

    files, duplicate_files = find_godot_project_files(project_directory)
    if not files:
        LOGGER.warn("No Godot project folder found, include patterns will need complete file paths.")
    if duplicate_files:
        LOGGER.warn("Found duplicate files in the project: " + str(duplicate_files))

    return panflute.run_filter(process_includes, doc=doc, files=files, duplicate_files=duplicate_files)


if __name__ == "__main__":
    main()
