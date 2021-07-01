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
import pprint
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

from datargs import arg, parse

INCLUDE_LOGGER = logging.getLogger("include")

ERROR_PROJECT_DIRECTORY_NOT_FOUND: int = 1
ERROR_ATTEMPT_TO_FIND_DUPLICATE_FILE: int = 2
ERROR_ANCHOR_NOT_FOUND: int = 3

REGEX_INCLUDE: re.Pattern = re.compile(
    r"^{% *include [\"']?(?P<file>.+?\.[a-zA-Z0-9]+)[\"']? [\"']?(?P<anchor>\w+)[\"']? *%}$",
    flags=re.MULTILINE,
)


@dataclass
class Args:
    input_file: Path = arg(
        positional=True, help="A single markdown file to process for include templates."
    )


def find_godot_project_files(project_directory: str) -> Tuple[dict, list]:
    """Maps the name of files in the project to their full path."""
    files: dict = {}
    duplicate_files: list = []
    include_extensions: set = {".gd", ".shader"}

    godot_directories: List[str] = list(
        filter(
            lambda name: os.path.isdir(os.path.join(project_directory, name))
            and "godot" in name,
            os.listdir(project_directory),
        )
    )

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
                    files[filename] = {"path": os.path.join(dirpath, filename)}
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
        return re.findall(r"# ?ANCHOR: ?(\w+)", content)

    anchor_map: dict = {}
    ANCHOR_REGEX_TEMPLATE = r"^\s*# ?ANCHOR: ?{}\s*\n(.+)\n\s*# ?END: ?{}"

    anchors = find_all_anchors_in_file(content)

    for anchor in anchors:
        regex_anchor: re.Pattern = re.compile(
            ANCHOR_REGEX_TEMPLATE.format(anchor, anchor), flags=re.DOTALL | re.MULTILINE
        )
        match: re.Match = regex_anchor.search(content)
        if not match:
            INCLUDE_LOGGER.error(
                'Malformed anchor pattern for anchor "{}"'.format(anchor)
            )
            sys.exit(ERROR_ATTEMPT_TO_FIND_DUPLICATE_FILE)
        anchor_content = re.sub(
            r"^\s*# (ANCHOR|END): \w+\s*$", "", match.group(1), flags=re.MULTILINE
        )
        anchor_map[anchor] = anchor_content
    return anchor_map


def replace_includes(content: str, files: dict, duplicate_files: list) -> str:
    def replace_include(match: re.Match) -> str:
        assert match.group("file") and match.group(
            "anchor"
        ), "Missing file or anchor in the include template."

        path: str = match.group("file")
        anchor: str = match.group("anchor")
        
        if "anchors" not in files[path]:
            content: str = get_file_content(path, files, duplicate_files)
            files[path]["anchors"] = find_all_file_anchors(content)

        anchors = files[path]["anchors"]
        if not anchor in anchors:
            INCLUDE_LOGGER.error(
                "Error: anchor {} not found in file {}. Aborting operation.".format(
                    anchor, path
                )
            )
            sys.exit(ERROR_ANCHOR_NOT_FOUND)
            
        anchor_content: str = files[path]["anchors"][anchor]
        return anchor_content

    return REGEX_INCLUDE.sub(replace_include, content)


def find_git_root_directory(file_path: Path) -> Path:
    """Attempts to find a .git directory, starting to the folder where we run the
    script and moving up the filesystem."""
    out: str = ""
    path: Path = file_path.parent
    for index in range(5):
        if Path(path, ".git").exists():
            out = path
            break
        path = path.parent
    return path


def process_document(file_path: str) -> str:
    output: str = ""
    project_directory: Path = find_git_root_directory(file_path)
    if not project_directory:
        INCLUDE_LOGGER.error("Project directory not found, aborting.")
        sys.exit(ERROR_PROJECT_DIRECTORY_NOT_FOUND)

    files, duplicate_files = find_godot_project_files(project_directory)
    if not files:
        INCLUDE_LOGGER.warning(
            "No Godot project folder found, include patterns will need complete file paths."
        )
    if duplicate_files:
        INCLUDE_LOGGER.warning(
            "Found duplicate files in the project: " + str(duplicate_files)
        )

    pprint.pprint(files.keys())
    with open(file_path, "r") as input_file:
        content: str = input_file.read()
        output = replace_includes(content, files, duplicate_files)

    return output


def main():
    args: Args = parse(Args)
    if not args.input_file.exists():
        INCLUDE_LOGGER.error(
            "File {} not found. Aborting operation.".format(args.input_file.as_posix())
        )
    output = process_document(args.input_file)
    print(output)


if __name__ == "__main__":
    main()
