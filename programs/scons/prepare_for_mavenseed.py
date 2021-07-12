#!/usr/bin/env python3
"""Extract the body of html files to upload them to Mavenseed."""
from dataclasses import dataclass
from pathlib import Path
from typing import List, Sequence

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


def main():
    args: Args = parse(Args)
    valid_filepaths: List[Path] = [p for p in args.filepaths if p.suffix == ".html"]

    if not args.output_directory.exists():
        print(f"Creating directory: {args.output_directory}")
        args.output_directory.mkdir(parents=True)

    overwrite_all: bool = args.overwrite
    for path in valid_filepaths:
        with open(path) as f:
            html_body: str = extract_html_body(f.read())
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
            with open(out_path, "w") as out_f:
                out_f.write(html_body)
                print(f"Wrote {out_path}")

    if args.print_files:
        print("\n".join(str(p) for p in valid_filepaths))


if __name__ == "__main__":
    main()
