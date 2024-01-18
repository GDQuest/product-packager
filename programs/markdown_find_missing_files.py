#!/usr/bin/env python
"""Program that takes a list of markdown or mdx files as an input, checks if the files have media files, and if they do, checks if the media files exist in the media files directory. If they don't, it prints the name of the file and the name of the image that is missing."""
import argparse
import os
import re


def main():
    parser = argparse.ArgumentParser(
        description="Find missing media files in markdown files."
    )
    parser.add_argument(
        "files",
        nargs="+",
        help="Markdown or MDX files to check for missing media files.",
    )
    args = parser.parse_args()
    args.files = [
        file for file in args.files if file.endswith(".md") or file.endswith(".mdx")
    ]
    if not args.files:
        raise ValueError("No valid markdown or MDX files provided.")

    missing_set = set()
    missing_media = {}
    for file in args.files:
        with open(file, "r") as f:
            lines = f.readlines()

            # Filter out lines in MDX comments
            filtered_lines = []
            in_comment = False
            for line in lines:
                if line.strip().startswith("{/*"):
                    in_comment = True
                if line.strip().endswith("*/}"):
                    in_comment = False
                    continue
                if not in_comment:
                    filtered_lines.append(line)

            for line in filtered_lines:
                match = re.search(r"!\[.*\]\((.*)\)|<VideoFile.*file=\"(.*)\" />", line)
                if not match:
                    continue

                media_file_path_markdown = match.group(1) or match.group(2)
                media_file_path_disk = media_file_path_markdown
                if not os.path.isabs(media_file_path_disk):
                    media_file_path_markdown = os.path.join(
                        os.path.dirname(file), media_file_path_markdown
                    )

                if os.path.isfile(media_file_path_markdown):
                    continue

                missing_set.add(media_file_path_markdown)
                if file not in missing_media:
                    missing_media[file] = []
                missing_media[file].append(media_file_path_markdown)

    output = []
    for file, media_file_paths in missing_media.items():
        output.append(f"Found {len(media_file_paths)} missing media files in {file}:")
        output.append("")
        for media_file_path_markdown in media_file_paths:
            output.append(f"- {media_file_path_markdown}")
        output.append("")

    print("\n".join(output))

    print("Total missing media files:", len(missing_set))


if __name__ == "__main__":
    main()
