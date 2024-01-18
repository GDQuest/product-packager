#!/usr/bin/env python3
"""Takes markdown files as input and outputs files with the code removed, but
not code comments (assumes comments start with #).

We use it to exclude lines of code from documents to translate, to count
translated words.

"""
import sys
import re


def remove_front_matter(content: str) -> str:
    """Removes front matter from markdown content"""
    return re.sub(r"^---\n(.*?)\n---", "", content, flags=re.S)


def remove_markdown_images(content: str) -> str:
    """Removes lines with markdown image tags from the content"""
    return re.sub(r"\!\[.*?\]\(.*?\)\n?", "", content)


def remove_hash_marks(content: str) -> str:
    """Removes hash marks from the content"""
    return re.sub("^#+ ", "", content, flags=re.M)


def remove_templates(content: str) -> str:
    """Removes markdown templates from the content"""
    return re.sub("\{\%.*\%\}", "", content)


def remove_list_items(content: str) -> str:
    """Removes list items from the content"""
    return re.sub("^(\d+\.)|(-) ", "", content, flags=re.M)


def merge_line_returns(content: str) -> str:
    """Merges line returns into a single line"""
    return re.sub("\n\n+", "\n\n", content)


def filter_out_code(content: str) -> str:
    """Finds code blocks in the markdown document"""

    def filter_code_comments(match):
        lines = match.group(2).split("\n")
        return "\n".join([line for line in lines if "# " in line])

    return re.sub("```([a-z]*)\n(.*?)```", filter_code_comments, content, flags=re.S)


def main():
    filepaths = [arg for arg in sys.argv if arg.endswith(".md")]
    for filepath in filepaths:
        with open(filepath, "r") as md_file:
            content = md_file.read()
            content = remove_front_matter(content)
            content = filter_out_code(content)
            content = remove_markdown_images(content)
            content = remove_hash_marks(content)
            content = remove_list_items(content)
            content = remove_templates(content)
            content = merge_line_returns(content)
            print(content.strip())


if __name__ == "__main__":
    main()
