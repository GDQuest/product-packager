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


def main():
    if shutil.which("po4a-gettextize") is None:
        print(
            "ERROR: po4a-gettextize is not installed. You need it to run this script. "
            "On Linux, you can install it from your package manager. On Debian-based distributions: `sudo apt install po4a`.\n\n"
            "On other sytems, you need to install it using the PERL language:\n\n"
            "- Download a release on GitHub https://github.com/mquinson/po4a/releases\n"
            "- Unpack the tarball\n"
            "- Read the README https://github.com/mquinson/po4a\n"
        )
        sys.exit(1)

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

    for file in translation_files:
        if not file.parent.exists():
            file.parent.mkdir(parents=True)

    for input_file, output_file in zip(markdown_files, translation_files):
        # "text" is the po4a format that supports markdown.
        command = ["po4a-gettextize", "--format", "text", "--master", str(input_file), "--po", str(output_file)]
        subprocess.run(command)


if __name__ == "__main__":
    main()
