"""Generates a changelog from a git repository."""
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from datargs import arg, parse

PATTERNS_MAP = {
    r"(Add)|(New):?": "New features",
    r"(Change)|(Update):?": "Changes",
    r"(Bug)|(Fix):?": "Bug fixes",
}


@dataclass
class Args:
    """Command-line arguments."""

    path: Path = arg(
        default=Path.cwd(), help="Path to the git repository", positional=True
    )
    title: str = arg(
        default="", aliases=["-t"], help="Title of the changelog"
    )
    commit_range: str = arg(
        aliases=["-c"],
        default="",
        help="""Range string to use to generate the changelog. If not set, the
        commit range will be from the last version tag to HEAD.""",
    )


def get_last_version_tag(args: Args = None) -> str:
    """Returns the last version tag."""
    git_describe_cmd = "git describe --tags --abbrev=0"
    describe = ""
    try:
        describe = subprocess.check_output(
            git_describe_cmd.split(), cwd=args.path
        ).decode()
    except subprocess.CalledProcessError:
        print(
            f"Could not get version tag from command '{git_describe_cmd}'. Is this a git repository?"
        )
        exit(1)
    describe = describe.strip()
    return describe


def generate_changelog(args: Args) -> str:
    """Generates a changelog from a git repository.

    Args:
        commit_range: The range to use to generate the changelog.

    Returns:
        A changelog string.
    """
    commit_range = args.commit_range

    if not commit_range:
        last_version_tag = get_last_version_tag(args)
        commit_range = f"{last_version_tag}..HEAD"

    changelog = f"## {args.title} release {commit_range.split('..')[0]}\n\n".replace("  ", " ")

    git_log_command = f"git log {commit_range} --pretty=format:'%s' --reverse".split()
    log = subprocess.check_output(git_log_command, cwd=args.path).decode()
    log = log.split("\n")
    log = [line.strip("'") for line in log]

    changelog_map = {value: [] for value in PATTERNS_MAP.values()}
    for line in log:
        for pattern, changelog_type in PATTERNS_MAP.items():
            if re.match(pattern, line):
                cleaned_line = re.sub(pattern, "", line).strip(" :")
                cleaned_line = cleaned_line[:1].capitalize() + cleaned_line[1:]
                changelog_map[changelog_type].append(cleaned_line)

    for changelog_type, changelog_list in changelog_map.items():
        if changelog_list:
            changelog += f"### {changelog_type}\n\n- "
            changelog += "\n- ".join(changelog_list)
            changelog += "\n\n"

    return changelog


def main():
    """Runs the program."""
    args = parse(Args)
    if not args.path.is_dir():
        raise ValueError(f"{args.path} is not a directory. Aborting operation.")

    print(generate_changelog(args))


if __name__ == "__main__":
    main()
