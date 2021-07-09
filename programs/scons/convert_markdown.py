#!/usr/bin/env python3
#
# Copyright (C) 2020 by Nathan Lovato and contributors
#
# This file is part of GDQuest product packager.
#
# GDQuest product packager is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation, either
# version 3 of the License, or (at your option) any later version.
#
# GDQuest product packager is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with GDQuest product
# packager. If not, see <https://www.gnu.org/licenses/>.
#
# Description:
#
# Converts markdown documents to self-contained HTML or PDF files using Pandoc.
import logging
import re
import subprocess
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Sequence

from datargs import arg, parse


class PdfEngines(Enum):
    pdfroff = "pdfroff"
    wkhtmltopdf = "wkhtmltopdf"
    weasyprint = "weasyprint"
    prince = "prince"


class OutputTypes(Enum):
    pdf = "pdf"
    html = "html"


LOGGER = logging.getLogger("convert_markdown.py")
THIS_DIRECTORY: Path = Path(__file__).parent

CONTENT_DIRECTORY: str = "content"
DEFAULT_CSS_FILE_PATH: Path = Path(THIS_DIRECTORY, "css/pandoc.css")
DEFAULT_DATA_DIRECTORY: Path = Path(THIS_DIRECTORY, "pandoc")

ERROR_CSS_INVALID: str = "Invalid CSS file. {} is not a valid file. Using default path {}."
PDF_ENGINE_MEMBERS = [member.value for member in PdfEngines]
HELP_PDF_ENGINE = ["PDF rendering engine to use if --type is pdf.",
                   "Supported PDF rendering engines: {}".format(", ".join(PDF_ENGINE_MEMBERS))]
HELP_CSS_FILE = "Path to the css file to use for rendering. Default: {}".format(
    DEFAULT_CSS_FILE_PATH)


@dataclass
class Args:
    files: Sequence[Path] = arg(positional=True,
                                help="A list of paths to markdown files.")
    output_directory: Path = arg(
        default=Path(), help="Path to the output directory.", aliases=["-o"])
    pdf_engine: PdfEngines = arg(
        default=PdfEngines.weasyprint, help="\n".join(HELP_PDF_ENGINE), aliases=["-p"])
    output_type: OutputTypes = arg(default=OutputTypes.html,
                                   help="Type of file to output, either html or pdf.", aliases=["-t"])
    css: Path = arg(default=DEFAULT_CSS_FILE_PATH, help=HELP_CSS_FILE, aliases=["-c"])
    pandoc_data_directory: Path = arg(
        default=DEFAULT_DATA_DIRECTORY, help="Path to a data directory to use for pandoc.", aliases=["-d"])
    filters: Sequence[str] = arg(default=(), aliases=['-f'],
                                 help="List of pandoc filters to run on each content file.")


def path_to_title(filepath: str) -> str:
    title: str = Path(filepath).stem
    title = re.sub(r"^\d*\.", "", title)
    title = re.sub(r"[\-_\/\\]", " ", title)
    return title


def get_output_path(args: Args, filepath: Path) -> Path:
    """Calculates and return the desired output file path."""
    directory_name: str = filepath.parent.name
    filename: str = filepath.stem
    filename += ".{}".format(args.output_type.value)
    return Path(args.output_directory, directory_name, filename)


def convert_markdown(args: Args, path: str) -> None:
    """Builds and runs a pandoc command to convert the input markdown document
    `path` to the desired output format."""
    title: str = path_to_title(path)
    pandoc_command = ["pandoc", path.absolute().as_posix(), "--self-contained", "--css", args.css.absolute().as_posix(),
                      "--metadata", "pagetitle='{}'".format(title), "--data-dir",
                      args.pandoc_data_directory.absolute().as_posix()]
    if args.output_type == OutputTypes.pdf:
        pandoc_command += ["--pdf-engine", args.pdf_engine]
    if args.filters:
        pandoc_command += ["--filter", *args.filters]
    output_path: Path = get_output_path(args, path)
    pandoc_command += ["--output", output_path.absolute().as_posix()]
    # To use pandoc's built-in syntax highlighter. The theme still needs some work.
    # PANDOC_DIRECTORY: Path = Path(THIS_DIRECTORY, "pandoc")
    # pandoc_command += [
        # "--syntax-definition",
        # Path(PANDOC_DIRECTORY, "gd-script.xml").absolute().as_posix(),
        # "--highlight-style",
        # Path(PANDOC_DIRECTORY, "gdscript.theme").absolute().as_posix()
    # ]

    if not output_path.parent.exists():
        output_path.parent.mkdir(parents=True)

    out = subprocess.run(pandoc_command, capture_output=True, cwd=path.parent)
    if out.returncode != 0:
        print(out.stderr.decode())
        raise Exception(out.stderr.decode())


def main():
    args: Args = parse(Args)
    for filepath in args.files:
        convert_markdown(args, filepath)


if __name__ == "__main__":
    main()
