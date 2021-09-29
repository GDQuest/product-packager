"""Linter for our tutorials.

Each function handles one linter rule."""

import inspect
import re
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Callable, Dict, List, Sequence

import yaml
from datargs import arg, parse

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
    empty_heading = "empty_heading"
    heading_ends_with_period = "heading_ends_with_period"
    list_item_ends_with_period = "list_item_ends_with_period"
    list_item_does_not_end_with_period = "list_item_doesnt_end_with_period"
    slash_between_items = "slash_between_items"
    missing_blank_line_before_list = "missing_blank_line_before_list"
    link_not_found = "link_not_found"


@dataclass
class Args:
    input_files: Sequence[Path] = arg(
        positional=True, help="One or more markdown files to lint."
    )
    print_errors: bool = arg(
        default=False,
        help="Prints extra error messages.",
        aliases=["-e"],
    )


@dataclass
class Function:
    name: str
    function: Callable


@dataclass
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
    error: str = ""


def check_yaml_frontmatter(document: Document) -> List[Issue]:
    """Check that the frontmatter is valid."""
    issues = []

    frontmatter_re = re.compile(r"---\n(.*?)\n---\n", re.DOTALL)
    match: re.Match = frontmatter_re.match(document.content)
    if not match or not match.group(1):
        issues.append(
            Issue(
                line=0,
                column_start=0,
                column_end=0,
                message=f"Missing frontmatter.",
                rule=Rules.yaml_frontmatter_missing,
            )
        )
    else:
        try:
            yaml.safe_load(match.group(1))
        except yaml.scanner.ScannerError as e:
            issues.append(
                Issue(
                    line=0,
                    column_start=0,
                    column_end=match.end(),
                    message=f"Invalid frontmatter.",
                    rule=Rules.yaml_frontmatter_invalid_syntax,
                    error=e,
                )
            )
    return issues


def check_tutorial_formatting(document: Document) -> List[Issue]:
    """Check that the tutorial is formatted correctly."""
    issues = []

    def check_title_exists(document: Document) -> Issue:
        issue = None
        title_re = re.compile(r"# (?P<title>[^#]+)")
        if not title_re.search(document.content):
            issue = Issue(
                line=0,
                column_start=0,
                column_end=0,
                message="Missing title.",
                rule=Rules.missing_title,
            )
        return issue

    def check_built_in_classes(document: Document) -> Issue:
        """Checks that there are no built-in classes without a code mark."""
        issue = None
        built_in_classes_re = re.compile(
            r"\b(?<!`)({})\b".format(r"|".join(BUILT_IN_CLASSES))
        )
        inside_code_block = False
        for number, line in enumerate(document.lines):
            if line.startswith("```"):
                inside_code_block = not inside_code_block
                continue
            # Skip headings and code blocks
            if line.startswith("#") or inside_code_block:
                continue
            # Skip templates
            if line.startswith("{%"):
                continue

            match = built_in_classes_re.search(line)
            # We ignore capitalized names at the start of a sentence as they can
            # be plain words like Animation, which match the built-in classes.
            if match and match.start() != 0:
                issue = Issue(
                    line=number + 1,
                    column_start=match.start(1),
                    column_end=match.end(1),
                    message=(
                        f"Found built-in class without code fences: {match.group(1)}. "
                        "Did you run the tutorial formatter?"
                    ),
                    rule=Rules.missing_formatting,
                )
                break
        return issue

    for function in [check_title_exists, check_built_in_classes]:
        issue = function(document)
        if issue is not None:
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
                column_start=0,
                column_end=len(line) - 1,
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
            nonlocal include_file_path
            nonlocal include_anchor
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
        if include_anchor == "":
            return None
        if include_file_path is None:
            print(document.path)
            raise Exception(
                "include_file_path must be a valid file to run this function."
            )
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
                    column_start=0,
                    column_end=0,
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
            if issue is not None:
                issues.append(issue)
                break

    return issues


def check_links(document: Document) -> List[Issue]:
    """Check that the link templates have the correct syntax."""

    def linked_file_exists(link: str, document: Document) -> bool:
        content_folder = document.git_directory.joinpath("content")
        assert (
            content_folder.exists()
        ), f"The git repository {document.git_directory} must have a content folder."

        found_files = list(content_folder.rglob(link))
        return found_files != []

    issues = []
    
    link_base_re = re.compile(r"{% *link .+ *%}")
    link_re = re.compile(r"{% *link [\"']?(?P<link>\w+)[\"']? ?(?P<target>[\w-]+)? *%}")
    for number, line in enumerate(document.lines):
        match = link_base_re.search(line)
        if not match:
            continue
        match_arguments = link_re.search(line)
        if not match_arguments:
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(),
                    column_end=match.end(),
                    message="Link syntax is incorrect.",
                    rule=Rules.link_syntax,
                )
            )
            continue
        link = match_arguments.group("link")
        if not re.match(r"(https?:)?//", link) and not linked_file_exists(
            link, document
        ):
            issues.append(
                Issue(
                    line=number + 1,
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
                line=number + 1,
                column_start=match.start(),
                column_end=match.end(),
                message="Found leftover TODO item.",
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

        path: Path = document.path.parent / match.group(1)
        if not path.is_file():
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(),
                    column_end=match.end(),
                    message=f"Missing picture {match.group(1)}.",
                    rule=Rules.missing_pictures,
                )
            )
    return issues


def check_lists(document: Document) -> List[Issue]:
    """Check that markdown lists items:

    - Are preceded by a blank line.
    - Are not left empty.
    - End with a period if they're a list of sentences.
    - End without a period if they're a list of items."""
    issues = []
    markdown_list_re = re.compile(r"\s*(\d+\.|-) \s*(.*)\n")

    is_front_matter = False
    is_inside_list = False
    for number, line in enumerate(document.lines):
        # We skip lines inside the front matter as that's YAML data.
        if line.startswith("---"):
            is_front_matter = not is_front_matter
        if is_front_matter:
            continue

        match = markdown_list_re.match(line)
        if not match:
            if is_inside_list:
                is_inside_list = False
            continue
        # Figure out if this is the first item in the list.
        # If it is, we need to check that the previous line was blank.
        if not is_inside_list:
            is_inside_list = True
            if document.lines[number - 1].strip() != "":
                issues.append(
                    Issue(
                        line=number + 1,
                        column_start=0,
                        column_end=0,
                        message="Missing blank line before list.",
                        rule=Rules.missing_blank_line_before_list,
                    )
                )

        content = match.group(2).strip()
        is_pascal_case_sequence = (
            re.match(r"^\*?[A-Z]\w*\*?( [A-Z]\w*)*\*?$", content) is not None
        )
        if is_pascal_case_sequence and content.endswith("."):
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(2),
                    column_end=match.end(2),
                    message="List item ends with a period.",
                    rule=Rules.list_item_ends_with_period,
                )
            )
        elif not is_pascal_case_sequence and not content[-1] in ".?!":
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(2),
                    column_end=match.end(2),
                    message="Sentence in list does not end with a period.",
                    rule=Rules.list_item_does_not_end_with_period,
                )
            )
        elif content.strip() == "":
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(),
                    column_end=match.end(),
                    message=f"Empty list item.",
                    rule=Rules.empty_lists,
                )
            )
    return issues


def check_headings(document: Document) -> List[Issue]:
    """Checks that markdown headings do not end with any punctuation and they're
    not empty."""
    issues = []
    markdown_heading_re = re.compile(r"#+\s*(?P<title>.*)")

    is_code_block = False
    for number, line in enumerate(document.lines):
        if line.startswith("```"):
            is_code_block = not is_code_block
        if is_code_block:
            continue

        match = markdown_heading_re.match(line)
        if not match:
            continue

        title = match.group("title")
        if title == "":
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(),
                    column_end=match.end(),
                    message="Empty heading.",
                    rule=Rules.empty_heading,
                )
            )
        elif title[-1] in ".":
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(),
                    column_end=match.end(),
                    message="Headings shouldn't end with a period. "
                    f"Found '{title[-1]}' at the end of the line.",
                    rule=Rules.heading_ends_with_period,
                )
            )
    return issues


def check_statements_with_slashes(document: Document) -> List[Issue]:
    """Reports issues regarding patterns like and/or."""
    issues = []
    markdown_and_or_re = re.compile(r"(and/or)|(or/and)")
    items_with_slashes_re = re.compile(r"\w+`? / `?\w+")

    for number, line in enumerate(document.lines):
        match = markdown_and_or_re.search(line)
        if match:
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(),
                    column_end=match.end(),
                    message=f"Don't use slashes between two words as in '{match.group(1)}'.",
                    rule=Rules.slash_between_items,
                )
            )
        match = items_with_slashes_re.search(line)
        if match:
            issues.append(
                Issue(
                    line=number + 1,
                    column_start=match.start(),
                    column_end=match.end(),
                    message=f"Don't use slashes in items like '{match.group(0)}'.",
                    rule=Rules.slash_between_items,
                )
            )
    return issues


def lint(path: Path) -> List[Issue]:
    """Lint a tutorial.

    Arguments:
        path: path to the tutorial
    """
    issues = []
    check_functions: List[Function] = [
        f for f in get_all_functions_in_module() if f.name.startswith("check_")
    ]
    with open(path) as input_file:
        lines = input_file.readlines()
        document = Document(path=path, lines=lines, content="".join(lines))
        for check_function in check_functions:
            issues += check_function.function(document)
    return issues


def get_all_functions_in_module() -> List[Function]:
    """Get all functions in this module."""
    return [
        Function(name, obj)
        for name, obj in inspect.getmembers(sys.modules[__name__])
        if inspect.isfunction(obj)
    ]


def main():
    args = parse(Args)
    issues_found: bool = False
    for path in args.input_files:
        if not path.is_file():
            print(f"{path} does not exist. Exiting.")
            exit(ERROR_FILE_DOES_NOT_EXIST)

        issues = lint(path)
        if issues:
            issues_found = True
            print(f"Found {len(issues)} issues in{path}.\n")
            for issue in sorted(issues, key=lambda i: i.line):
                print(
                    f"{issue.rule.value} {issue.line}:{issue.column_start}-{issue.column_end} {issue.message}"
                )
                if args.print_errors and issue.error:
                    print(f"\nError message:\n\n{issue.error}")
    if issues_found:
        exit(ERROR_ISSUES_FOUND)


if __name__ == "__main__":
    main()
