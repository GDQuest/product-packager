#!/usr/bin/env python3
"""Extract the body of html files and replaces links to make them work on
Mavenseed."""
from dataclasses import dataclass
from pathlib import Path
from typing import List, Sequence
import re

from datargs import arg, parse


@dataclass
class Args:
    """Program command-line arguments."""

    filepaths: Sequence[Path] = arg(
        positional=True, help="A list of files to process for Mavenseed."
    )
    print_files: bool = arg(
        aliases=["-p"],
        default=False,
        help="Print the file paths output after processing them,"
        "to pass to another program to upload them.",
    )
    output_directory: Path = arg(
        default=Path("."), help="The directory to output files to.", aliases=["-o"]
    )
    overwrite: bool = arg(
        default=False, help="If True, overwrite existing output files.", aliases=["-w"]
    )


def extract_html_body(html: str) -> str:
    """Returns the content of the html <body> tag."""
    body_start = html.index("<body>") + 6
    body_end = html.index("</body>")
    return html[body_start:body_end]


def replace_links(html: str) -> str:
    """Finds links in the html document and removes the leading directory."""

    def replace_link(match):
        link = match.group(1)
        target_filename = Path(link).name
        if not target_filename.endswith(".html"):
            target_filename += ".html"
        title_id = get_document_h1_id(target_filename)
        return f'href="{title_id}"' if title_id else f'href="{link}"'

    return re.sub(r'href="(?!http|\/\/|#)(.+?)"', replace_link, html)


def get_document_h1_id(html_file_name: str) -> str:
    """Finds the html file by name from MAVENSEED_DIRECTORY and returns its h1
    tag's ID."""

    def find_file_by_name(file_name: str) -> Path:
        """Finds the file with the name file_name inside any subdirectory of the
        mavenseed_directory."""
        matching_files = list(DIST_DIRECTORY.rglob("**/" + file_name))
        return matching_files[0] if matching_files else None

    html_file = find_file_by_name(html_file_name)
    if html_file is None:
        print(f"Unable to find {html_file_name} in {DIST_DIRECTORY}")
        return ""

    with open(html_file, "r") as f:
        html = f.read()
        match = re.search(r'<h1 id="([^"]+)"', html)
        return match.group(1) if match else ""


def main():
    def find_dist_directory(start_file: Path) -> Path:
        max_iterations = 10
        path = start_file
        for _ in range(max_iterations):
            if path.stem == "dist":
                return path
            path = path.parent
        return None

    args: Args = parse(Args)
    valid_filepaths: List[Path] = [p for p in args.filepaths if p.suffix == ".html"]

    if not args.output_directory.exists():
        print(f"Creating directory: {args.output_directory}")
        args.output_directory.mkdir(parents=True)

    global DIST_DIRECTORY
    DIST_DIRECTORY = find_dist_directory(valid_filepaths[0])
    if DIST_DIRECTORY is None:
        print("Unable to find mavenseed directory.")
        exit(1)

    # Extract the body tag, replace links and move files to the output
    # directory.
    overwrite_all: bool = args.overwrite
    for path in valid_filepaths:
        with open(path) as f_in:
            html: str = f_in.read()
            html_body: str = extract_html_body(html)
            html_body = replace_links(html_body)
            out_path: Path = args.output_directory / (path.stem + ".html")

            if not overwrite_all and out_path.exists():
                overwrite_prompt = f"""{out_path} already exists. Overwrite?

                - [y]: yes for this file
                - [N]: no for this file
                - [A]: yes to all"""
                prompt: str = input(overwrite_prompt)
                overwrite_all = prompt == "A"
                overwrite_this_file: bool = prompt.lower() == "y"

                if not overwrite_this_file:
                    continue
            with open(out_path, "w") as f_out:
                f_out.write(html_body)
                print(f"Wrote {out_path}")

    if args.print_files:
        print("\n".join(str(p) for p in valid_filepaths))


if __name__ == "__main__":
    main()
