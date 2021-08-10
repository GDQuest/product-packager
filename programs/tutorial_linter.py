"""Linter for our tutorials.

Each function handles one linter rule."""

import dataclasses
from dataclasses import dataclass
from typing import List, Sequence
import re
from pathlib import Path
from datargs import arg, parse
from enum import Enum
import yaml

from lib.gdscript_classes import BUILT_IN_CLASSES

ERROR_FILE_DOES_NOT_EXIST = 1
ERROR_ISSUES_FOUND = 2

MAX_FOLDER_ITERATIONS = 10


class Rules(Enum):
    """Linter rules that can be checked."""

    leftover_todo = "leftover_todo"
    empty_lists = "empty_lists"
    missing_pictures = "missing_pictures"
    missing_formatting = "missing_formatting"
    include_syntax = "include_syntax"
    include_missing_code_fences = "include_missing_code_fences"
    include_file_not_found = "include_file_not_found"
    include_anchor_not_found = "include_anchor_not_found"
    missing_title = "missing_title"
    link_syntax = "links_syntax"
    link_file_not_found = "link_file_not_found"
    yaml_frontmatter_missing = "yaml_frontmatter_missing"
    yaml_frontmatter_invalid_syntax = "yaml_frontmatter_invalid_syntax"


@dataclass
class Args:
    input_files: Sequence[Path] = arg(
        positional=True, help="One or more markdown files to lint."
    )


@dataclasses
class Document:
    """A document to be checked."""

    path: Path
    lines: List[str]
    content: str
    git_directory: Path = None

    def __post_init__(self):
        self.git_directory = self.find_git_directory()

    def find_git_directory(self):
        """Find the git directory for this file."""
        self.git_directory = self.path.parent.joinpath(".git")
        path: Path = self.path.parent
        for index in range(MAX_FOLDER_ITERATIONS):
            if Path(path, ".git").exists():
                break
            path = path.parent
        return path


@dataclass
class Issue:
    line: int
    column_start: int
    column_end: int
    message: str
    rule: str


def check_yaml_frontmatter(document: Document) -> List[Issue]:
    """Check that the frontmatter is valid."""
    issues = []

    frontmatter_re = re.compile(r"---\n(.*?)\n---\n", re.DOTALL)
    match: re.Match = frontmatter_re.match(document.content)
    if not match or not match.group(1):
        issues.append(
            Issue(
                line=document.lines[0],
                column_start=0,
                column_end=0,
                message=f"Missing frontmatter in {document.path}",
                rule=Rules.yaml_frontmatter_missing,
            )
        )
    elif not yaml.safe_load(match.group(1)):
        issues.append(
            Issue(
                line=document.lines[0],
                column_start=0,
                column_end=match.end(),
                message=f"Invalid frontmatter in {document.path}",
                rule=Rules.yaml_frontmatter_invalid_syntax,
            )
        )
    return issues


def check_tutorial_formatting(document: Document) -> List[Issue]:
    """Check that the tutorial is formatted correctly."""
    issues = []

    def check_title_exists(document: Document) -> Issue:
        issue = None
        title_re = re.compile(r"^# (?P<title>[^#]+)")
        if not title_re.search(document.content):
            issue = Issue(
                line=0,
                column_start=0,
                column_end=0,
                message="Missing title",
                rule=Rules.missing_title,
            )
        return issue

    def check_built_in_classes(document: Document) -> Issue:
        """Checks that there are no built-in classes without a code mark."""
        issue = None
        built_in_classes_re = re.compile(
            r"\b(?<!`)({})\b".format(r"|".join(BUILT_IN_CLASSES))
        )
        if built_in_classes_re.search(document.content):
            issue = Issue(
                line=0,
                column_start=0,
                column_end=0,
                message="Found built-in class without code fence. Did you run the tutorial formatter?",
                rule=Rules.missing_formatting,
            )
        return issue

    for function in [check_title_exists, check_built_in_classes]:
        issue = function(document)
        if issue:
            issues.append(issue)

    return issues


def check_includes(document: Document) -> List[Issue]:
    """Finds all includes in the document and for each, checks that:

    - The include template have the correct syntax.
    - The include file exist.
    - The include anchor exists inside the target file.

    In this order. The function will return the first issue it finds for each
    include."""

    include_re = re.compile(
        r"{% *include.+%}",
    )
    include_syntax_re = re.compile(
        r"{% *include [\"']?(?P<file>.+?\.[a-zA-Z0-9]+)[\"']? *[\"']?(?P<anchor>\w+)?[\"']? *%}",
    )
    include_file_path: Path = None
    include_anchor = ""

    def check_include_syntax(line: str, index: int) -> Issue:
        issue = None
        match = include_syntax_re.match(line)
        if not match:
            issue = Issue(
                line=index,
                column_start=match.start(),
                column_end=match.end(),
                message="Include syntax is incorrect.",
                rule=Rules.include_syntax,
            )
        return issue

    def check_include_file_exists(line: str, index: int) -> Issue:
        issue = None
        match = include_syntax_re.match(line)

        file_exists = False
        found_files = document.git_directory.rglob(match.group("file"))
        for f in found_files:
            include_file_path = document.git_directory.joinpath(f)
            include_anchor = match.group("anchor")
            file_exists = include_file_path.exists()
            break

        if not file_exists:
            issue = Issue(
                line=index,
                column_start=match.start(),
                column_end=match.end(),
                message=f"Include file {match.group('file')} not found.",
                rule=Rules.include_file_not_found,
            )

        return issue

    def check_include_anchor_exists(line: str, index: int) -> Issue:
        assert (
            include_file_path is not None
        ), "include_file_path must be a valid file to run this function."
        issue = None
        anchor_re = re.compile(
            r"^\s*# ?ANCHOR: ?{}\s*\n(.+)\n\s*# ?END: ?{}".format(
                include_anchor, include_anchor
            ),
            flags=re.DOTALL | re.MULTILINE,
        )
        with open(include_file_path, "r") as include_file:
            content = include_file.read()
            match = anchor_re.search(content)
            if not match:
                issue = Issue(
                    line=index,
                    column_start=anchor_re.search(content).start(),
                    column_end=anchor_re.search(content).end(),
                    message=f"Include anchor {include_anchor} not found in {include_file_path}.",
                    rule=Rules.include_anchor_not_found,
                )
        return issue

    issues = []
    for number, line in enumerate(document.lines):
        match = include_re.match(line)
        if not match:
            continue

        for check_function in [
            check_include_syntax,
            check_include_file_exists,
            check_include_anchor_exists,
        ]:
            issue = check_function(line, number)
            if issue:
                issues.append(issue)
                break

    return issues


def check_links(document: Document) -> List[Issue]:
    """Check that the link templates have the correct syntax."""

    def linked_file_exists(link: str, document: Document) -> bool:
        content_folder = document.git_directory.joinpath("content")
        assert (
            content_folder.exists(),
            f"The git repository {document.git_directory} must have a content folder.",
        )
        found_files = list(content_folder.rglob(link))
        return found_files != []

    issues = []
    link_base_re = re.compile(r"{% *link.+%}")
    link_re = re.compile(r"{% *link [\"']?(?P<link>.+?)[\"']? *(?P<target>\w+)? *%}")
    for number, line in enumerate(document.lines):
        match = link_base_re.match(line)
        if not match:
            continue
        match_arguments = link_re.match(line)
        if not match_arguments:
            issues.append(
                Issue(
                    line=number,
                    column_start=match.start(),
                    column_end=match.end(),
                    message="Link syntax is incorrect.",
                    rule=Rules.link_syntax,
                )
            )
            continue
        link = match_arguments.group("link")
        if not re.match(r"(https?:)?//", link) and not linked_file_exists(
            link, document.path
        ):
            issues.append(
                Issue(
                    line=number,
                    column_start=match.start(),
                    column_end=match.end(),
                    message=f"Linked file {match_arguments.group('link')} not found.",
                    rule=Rules.link_not_found,
                )
            )

    return issues


def check_todos(document: Document) -> List[Issue]:
    """Check that there are no TODO items left inside the document."""
    issues = []
    todo_re = re.compile(r"\s*TODO\s*", re.IGNORECASE)
    for number, line in enumerate(document.lines):
        match = todo_re.search(line)
        if not match:
            continue
        issues.append(
            Issue(
                line=number,
                column_start=match.start(),
                column_end=match.end(),
                message="Found leftover TODO item",
                rule=Rules.leftover_todo,
            )
        )
    return issues


def check_missing_pictures(document: Document) -> List[Issue]:
    """Check that all pictures files linked in the document exist."""
    issues = []
    markdown_picture_re = re.compile(r"\s*\!\[.*\]\((.*)\)")

    for number, line in enumerate(document.lines):
        match = markdown_picture_re.match(line)
        if not match:
            continue

        path: Path = document.path / match.group(1)
        if not path.is_file():
            issues.append(
                Issue(
                    line=number,
                    column_start=match.start(),
                    column_end=match.end(),
                    message=f"Missing picture {match.group(1)}",
                    rule=Rules.missing_pictures,
                )
            )
    return issues


def check_empty_lists(document: Document) -> List[Issue]:
    """Check that markdown lists items are not left empty."""
    issues = []
    markdown_list_re = re.compile(r"\s*(?P<type>- [^\n]*)\n")

    for number, line in enumerate(document.lines):
        match = markdown_list_re.match(line)
        if not match:
            continue
        issues.append(
            Issue(
                line=number,
                column_start=match.start(),
                column_end=match.end(),
                message=f"Empty list item",
                rule=Rules.empty_lists,
            )
        )


def lint(path: Path) -> List[Issue]:
    """Lint a tutorial.

    Arguments:
        path: path to the tutorial
    """
    issues = []
    check_functions = [m for m in dir() if m.startswith("check_")]
    with open(path) as file:
        lines = file.readlines()
        document = Document(path=path, lines=lines, content="".join(lines))
        for check_function in check_functions:
            issues += check_function(document)
    return issues


def main():
    args = parse(Args)
    issues = []
    for path in args.input_files:
        if not path.is_file():
            print(f"{path} does not exist. Exiting.")
            exit(ERROR_FILE_DOES_NOT_EXIST)
        issues = lint(path)
    if issues:
        print(f"Found {len(issues)} issues.")
        for issue in issues:
            print(
                f"{issue.rule} {issue.line}:{issue.column_start}-{issue.column_end} {issue.message}"
            )
        exit(ERROR_ISSUES_FOUND)


if __name__ == "__main__":
    main()
