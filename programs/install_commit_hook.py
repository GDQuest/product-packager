"""Copies and installs the commit hook checker script to the target repository."""

import argparse
import stat
import platform
from enum import Enum
from pathlib import Path


class Errors(Enum):
    MISSING_DIRECTORY_PATH = 1
    NOT_A_REPOSITORY = 2


def parse_args():
    """Parse the command line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "repository",
        type=Path,
        help="The path to the target repository.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    git_path: Path = args.repository / ".git"
    if not args.repository.is_dir():
        print(f"{args.repository} is not a directory. Exiting.")
        exit(Errors.MISSING_DIRECTORY_PATH.value)
    if not git_path.exists():
        print(f"{args.repository} is not a git repository. Exiting.")
        exit(Errors.NOT_A_REPOSITORY.value)

    print(f"Installing commit hook script to {args.repository}")
    commit_hook_script_path = Path(__file__).parent.joinpath("commit_message_hook.py")
    target_path = git_path / "hooks" / "commit-msg"
    if target_path.exists():
        print(f"{target_path} already exists. Deleting it.")
        target_path.unlink()
    hook_script = commit_hook_script_path.read_text()
    # On Linux we need to use the `python3` executable to run the script, but on
    # windows it's `python`.
    if platform.system()== "Windows":
        hook_script = hook_script.replace("python3", "python", 1)
    print(f"Copying the commit hook script to {target_path}")
    target_path.write_text(hook_script)
    print("Making the script executable.")
    target_path.chmod(target_path.stat().st_mode | stat.S_IEXEC)
    print("Done.")


if __name__ == "__main__":
    main()
