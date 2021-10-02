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
from pathlib import Path
from typing import List, Tuple

from datargs import arg, parse

from scons_helper import print_error

INCLUDE_LOGGER = logging.getLogger("include")

ERROR_PROJECT_DIRECTORY_NOT_FOUND: int = 1
ERROR_ATTEMPT_TO_FIND_DUPLICATE_FILE: int = 2
ERROR_ANCHOR_NOT_FOUND: int = 3

REGEX_INCLUDE: re.Pattern = re.compile(
    r"^{% *include [\"']?(?P<file>.+?\.[a-zA-Z0-9]+)[\"']? *[\"']?(?P<anchor>\w+)?[\"']? *%}$",
    flags=re.MULTILINE,
)
INCLUDE_EXTENSIONS: set = {".gd", ".shader"}


@dataclass
class Args:
    input_file: Path = arg(
        positional=True, help="A single markdown file to process for include templates."
    )


def find_godot_project_files(file_path: Path) -> List[Path]:
    files: List[Path] = []

    project_directory: Path = find_git_root_directory(file_path)
    if not project_directory:
        print_error("Project directory not found, aborting.")
        sys.exit(ERROR_PROJECT_DIRECTORY_NOT_FOUND)

    godot_directories: List[str] = list(
        filter(
            lambda name: os.path.isdir(os.path.join(project_directory, name))
            and "godot" in name,
            os.listdir(project_directory),
        )
    )
    if not godot_directories:
        INCLUDE_LOGGER.warning(
            "No Godot project folder found, include patterns will need complete file paths."
        )

    for directory_name in godot_directories:
        godot_directory = os.path.join(project_directory, directory_name)

        for dirpath, dirnames, filenames in os.walk(godot_directory):
            directory_path: Path = Path(dirpath)
            dirnames = [d for d in dirnames if not d.startswith(".")]
            for filename in filenames:
                if os.path.splitext(filename)[-1].lower() not in INCLUDE_EXTENSIONS:
                    continue
                files.append(directory_path / filename)
    return files


def find_duplicate_files(files: List[Path]) -> Tuple[dict, set]:
    """Maps the name of files in the project to their full path and finds duplicate filenames."""
    files_map: dict = {}
    duplicate_files: set = set()

    for f in files:
        filename = f.name
        if filename in files_map:
            duplicate_files.add(filename)
        else:
            files_map[filename] = {"path": str(f)}

    if duplicate_files:
        print_error(
            "Found duplicate files in the project: " + str(duplicate_files)
        )
    return files_map, duplicate_files


def get_file_content(file_path: str, files: dict, duplicate_files: list) -> str:
    """Returns the content of a file, finding it if `file_path` is only a file name."""

    def is_filename(file_path: str) -> bool:
        """Returns `True` if the provided path does not contain a slash character."""
        return file_path.find("/") == -1 and file_path.find("\\") == -1

    content: str = ""
    if is_filename(file_path):
        assert (
            file_path not in duplicate_files
        ), f"The requested file to include has duplicates with the same name in the project: {file_path}"
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
        regex_pattern = ANCHOR_REGEX_TEMPLATE.format(anchor, anchor)
        regex_anchor: re.Pattern = re.compile(
            regex_pattern, flags=re.DOTALL | re.MULTILINE
        )
        match: re.Match = regex_anchor.search(content)
        if not match:
            print_error(f'Malformed anchor pattern for anchor "{anchor}". '
            f'The following anchor regex failed to find a match: {regex_pattern}')
            sys.exit(ERROR_ATTEMPT_TO_FIND_DUPLICATE_FILE)
        anchor_content = re.sub(
            r"^\s*# *(ANCHOR|END): *\w+\s*$", "", match.group(1), flags=re.MULTILINE
        )
        anchor_map[anchor] = anchor_content
    return anchor_map


def replace_includes(content: str, files: dict, duplicate_files: list) -> str:
    def replace_include(match: re.Match) -> str:
        output: str = ""

        assert match.group("file"), "Missing file in the include template."

        path: str = match.group("file")
        anchor: str = match.group("anchor")

        # If there's no anchor specified, include the entire file.
        if not anchor:
            output = get_file_content(path, files, duplicate_files)
        else:
            if "anchors" not in files[path]:
                content: str = get_file_content(path, files, duplicate_files)
                files[path]["anchors"] = find_all_file_anchors(content)

            anchors = files[path]["anchors"]
            if not anchor in anchors:
                print_error(
                    "Error: anchor {} not found in file {}. Aborting operation.".format(
                        anchor, path
                    )
                )
                sys.exit(ERROR_ANCHOR_NOT_FOUND)
            anchor_content: str = files[path]["anchors"][anchor]
            output = anchor_content
        return output

    return REGEX_INCLUDE.sub(replace_include, content)


def find_git_root_directory(file_path: Path) -> Path:
    """Attempts to find a .git directory, starting to the folder where we run the
    script and moving up the filesystem."""
    path: Path = file_path.parent
    for index in range(5):
        if Path(path, ".git").exists():
            break
        path = path.parent
    return path


def process_document(
    content: str,
    document_path: Path,
    project_files: List[Path] = [],
    files_map: dict = {},
    duplicate_files: set = set(),
) -> str:
    output: str = ""

    # We allow external programs like a build system to probe and cache the
    # project files once. This is why we check for the arguments passed, to
    # distinguish this case from a standalone run of the program.
    # That way, in a build system, you'll only get file warnings once.
    if project_files == [] and files_map == {}:
        project_files = find_godot_project_files(document_path)
    if files_map == {}:
        files_map, duplicate_files = find_duplicate_files(project_files)

    output = replace_includes(content, files_map, duplicate_files)
    return output


def main():
    output: str = ""
    args: Args = parse(Args)
    if not args.input_file.exists():
        print_error(
            "File {} not found. Aborting operation.".format(args.input_file.as_posix())
        )

    with open(args.input_file, "r") as input_file:
        content: str = input_file.read()
        output = process_document(content, args.input_file)
    print(output)


if __name__ == "__main__":
    main()
