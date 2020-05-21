#!/usr/bin/env python3

"""Finds code blocks in markdown documents and runs their content through the code highlighting
program Chroma. Requires `chroma` to be installed and available on the PATH variable."""

import subprocess
import argparse
import re
import sys
import os
from os.path import basename, join


ERROR_CHROMA_NOT_FOUND = "Program chroma not found. You need chroma to be installed and available on PATH to use this program."

COMMAND_HIGHLIGHT = [
    "chroma",
    "--html",
    "--html-only",
    "--html-lines",
    "--html-inline-styles",
    "--style=monokai",
]


def highlight_code_blocks(file_path: str) -> str:
    """Finds code blocks in the markdown document"""

    def highlight_with_chroma(match):
        language = match.group(1)
        if language == "":
            language = "gdscript"

        command = COMMAND_HIGHLIGHT + ["--lexer=" + language]
        result = subprocess.run(
            command, input=match.group(2), stdout=subprocess.PIPE, text=True,
        )
        return result.stdout if result.returncode == 0 else match.string

    with open(file_path, "r") as md_file:
        return re.sub(
            "```([a-z]*)\n(.*?)```", highlight_with_chroma, md_file.read(), flags=re.S
        )
        return re.sub(
            "```([a-z]*)\n(.*?)```", highlight_with_chroma, md_file.read(), flags=re.S
        )


def is_chroma_installed():
    return (
        subprocess.run(["chroma", "--version"], stdout=subprocess.DEVNULL).returncode
        == 0
    )


def get_args(args) -> argparse.Namespace:
    """Parses the command line arguments"""
    parser = argparse.ArgumentParser(description=__doc__,)
    parser.add_argument(
        "files",
        type=str,
        nargs="+",
        default="",
        help="A list of paths to markdown files.",
    )
    parser.add_argument(
        "-o", "--output", type=str, default="", help="Path to the output directory.",
    )
    parser.add_argument(
        "-i", "--in-place", action="store_true", help="Overwrite the source files."
    )
    return parser.parse_args(args)


def main():
    if not is_chroma_installed():
        raise ProcessLookupError(ERROR_CHROMA_NOT_FOUND)

    args: argparse.Namespace = get_args(sys.argv)
    filepaths = [f for f in args.files if f.lower().endswith(".md")]
    for filepath in filepaths:
        content = highlight_code_blocks(filepath)

        # If no --output option set, output to stdout
        if args.output == "":
            print(content)
        else:
            out_path = join(args.output, basename(filepath))
            if not os.path.isdir(args.output):
                os.makedirs(args.output)
            with open(out_path, "w") as document:
                document.write(content)


if __name__ == "__main__":
    main()
