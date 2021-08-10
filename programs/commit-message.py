import re
import sys

VALID_COMMIT_TYPES = [
    "build",
    "chore",
    "ci",
    "docs",
    "feat",
    "fix",
    "improvement" "perf",
    "refactor",
    "revert",
    "style",
    "test",
]
COMMIT_EXAMPLES = """- feat: add interface for the fishing mini-game
- feat(combat): add triple laser beam combo
- fix: crash when attacking an enemy from behind
- improvement: more responsive player controls"""

ERROR_MESSAGE_INCORRECT_TYPE = f"""The type of commit at the start must be one of {", ".join(VALID_COMMIT_TYPES)}

Examples:
{COMMIT_EXAMPLES}
"""
ERROR_MESSAGE_INCORRECT_STRUCTURE = f"""The commit message's structure should match the conventional commit style.

Examples:
{COMMIT_EXAMPLES}
"""


def main():
    type_pattern = f"({'|'.join(VALID_COMMIT_TYPES)})"
    commit_filename = sys.argv[1]
    commit_message = ""
    with open(commit_filename, "r") as f:
        commit_message = f.read()

    type_match = re.match(type_pattern, commit_message)
    if not type_match:
        print(ERROR_MESSAGE_INCORRECT_TYPE)
        exit(1)

    complete_pattern = f"{type_pattern}(\([\w\-]+\))?:\s.*"
    match = re.match(complete_pattern, commit_message)
    if not match:
        print(ERROR_MESSAGE_INCORRECT_STRUCTURE)
        exit(1)


if __name__ == "__main__":
    main()
