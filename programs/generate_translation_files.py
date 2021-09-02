"""Finds markdown files in a project's content/ directory and generates or updates .po files."""

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List
import subprocess
import shutil

from datargs import arg, parse

DEFAULT_CONTENT_DIRNAME = "content"
DEFAULT_TRANSLATION_DIRNAME = "translations"
DEFAULT_LANGUAGE_CODE = "es"


@dataclass
class Args:
    project_path: Path = arg(positional=True, help="Path to the project's repository.")
    language_code: str = arg(
        default=DEFAULT_LANGUAGE_CODE, help="Language code for the translation files."
    )
    content_dirname: str = arg(
        default=DEFAULT_CONTENT_DIRNAME,
        help="Name of the directory containing markdown files.",
    )
    translation_dirname: str = arg(
        default=DEFAULT_TRANSLATION_DIRNAME,
        help="Name of the directory to output translation files.",
    )


def calculate_target_file_paths(
    destination: Path, relative_to: Path, source_files: list[Path]
) -> list[Path]:
    """Returns the list of files taking their path from relative_to and
    appending it to destination."""
    return


def main():
    args = parse(Args)
    content_directory: Path = args.project_path / args.content_dirname
    translation_directory: Path = args.project_path / args.translation_dirname
    if not content_directory.exists():
        print(f"ERROR: {content_directory} does not exist.")
        sys.exit(1)

    markdown_files: List[Path] = [p for p in content_directory.rglob("*.md")]
    translation_files: List[Path] = [
        translation_directory
        / args.language_code
        / sf.relative_to(content_directory).parent
        / sf.name.replace(".md", ".po", 1)
        for sf in markdown_files
    ]
    print(f"Found {len(markdown_files)} markdown files to translate.")
    print(f"Generating {len(translation_files)} translation files.")

    if shutil.which("gettext-md") is None:
        print(
            "ERROR: gettext-md is not installed. You need it to run this script. "
            "See install instructions here: https://www.npmjs.com/package/gettext-markdown"
        )
        sys.exit(1)

    for file in translation_files:
        if not file.parent.exists():
            file.parent.mkdir(parents=True)

    for input_file, output_file in zip(markdown_files, translation_files):
        command = ["gettext-md", "-o", str(output_file), "--pot", str(input_file)]
        subprocess.run(command)


if __name__ == "__main__":
    main()