#!/usr/bin/env python3
"""Takes markdown files as input and outputs files with the code removed, but
not code comments (assumes comments start with #).

We use it to exclude lines of code from documents to translate, to count
translated words.

"""
import sys
import re

def filter_out_code(file_path: str) -> str:
    """Finds code blocks in the markdown document"""

    def filter_code_comments(match):
        lines = match.group(2).split("\n")
        return "\n".join([line for line in lines if "# " in line])

    with open(file_path, "r") as md_file:
        return re.sub(
            "```([a-z]*)\n(.*?)```", filter_code_comments, md_file.read(), flags=re.S
        )


def main():
    filepaths = [arg for arg in sys.argv if arg.endswith(".md")]
    for filepath in filepaths:
        with open(filepath.replace('.md', '') + "_out.md", 'w') as output_file:
            output_file.write(filter_out_code(filepath))


if __name__ == '__main__':
    main()
