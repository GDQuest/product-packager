#!/usr/bin/env python3
"""Copies, cleans up, and zips a single Godot project."""

import logging
import sys
import os
import argparse
import tempfile
import shutil

LOGGER = logging.getLogger("package_godot_project.py")

ERROR_GODOT_DIRECTORY_NOT_FOUND: int = 1
ERROR_GODOT_DIRECTORY_INVALID: int = 2
ERROR_OUTPUT_DIRECTORY_INVALID: int = 3


def parse_command_line_arguments(args) -> argparse.Namespace:
    """Parses the command line arguments"""
    parser = argparse.ArgumentParser(description=__doc__,)
    parser.add_argument(
        "godot_directory",
        type=str,
        default="",
        help="Path to a Godot project directory.",
    )
    parser.add_argument(
        "-o", "--output", type=str, default=".", help="Path to the output directory.",
    )
    parser.add_argument(
        "-t",
        "--title",
        type=str,
        default="godot",
        help="Controls the output directory and zip file name.",
    )
    return parser.parse_args(args)


def main():
    args = parse_command_line_arguments(sys.argv[1:])
    src: str = args.godot_directory
    target_folder_name: str = args.title
    output_folder: str = os.path.abspath(args.output)

    # Check input and output directories.
    if not os.path.exists(src):
        LOGGER.error("Directory {} does not exist, aborting operation.".format(src))
        sys.exit(ERROR_GODOT_DIRECTORY_NOT_FOUND)
    if not os.path.isfile(os.path.join(src, "project.godot")):
        LOGGER.error(
            "Directory {} is not a Godot project, aborting operation.".format(src)
        )
        sys.exit(ERROR_GODOT_DIRECTORY_INVALID)
    if not os.path.isdir(output_folder):
        LOGGER.error(
            "Output directory {} does not exist. Aborting operation.".format(
                output_folder
            )
        )
        sys.exit(ERROR_OUTPUT_DIRECTORY_INVALID)

    with tempfile.TemporaryDirectory() as temporary_directory:
        target_directory: str = os.path.join(temporary_directory, target_folder_name)
        shutil.copytree(
            src, target_directory, ignore=shutil.ignore_patterns(".import", ".git")
        )
        archive_path: str = shutil.make_archive(
            target_folder_name, "zip", target_directory
        )
        if output_folder != ".":
            output_filename: str = os.path.join(output_folder, os.path.basename(archive_path))
            os.rename(archive_path, output_filename)


if __name__ == "__main__":
    main()
