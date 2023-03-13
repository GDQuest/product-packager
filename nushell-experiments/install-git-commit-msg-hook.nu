#!/usr/bin/env nu

let git_commit_msg_hook = (echo `#!/usr/bin/env python3
import re
import sys

valid_commit_types = [
    "build",
    "chore",
    "ci",
    "docs",
    "feat",
    "fix",
    "improvement",
    "perf",
    "refactor",
    "revert",
    "style",
    "test",
]
commit_examples = """- feat: add interface for the fishing mini-game
- feat(combat): add triple laser beam combo
- fix: crash when attacking an enemy from behind
- improvement: more responsive player controls"""

error_message_incorrect_type = f"""the type of commit at the start must be one of {", ".join(valid_commit_types)}

examples:
{commit_examples}
"""
error_message_incorrect_structure = f"""the commit message's structure should match the conventional commit style.

examples:
{commit_examples}
"""


def main():
    type_pattern = f"({'|'.join(valid_commit_types)})"
    commit_filename = sys.argv[1]
    commit_message = ""
    with open(commit_filename, "r") as f:
        commit_message = f.read()

    type_match = re.match(type_pattern, commit_message)
    if not type_match:
        print(error_message_incorrect_type)
        exit(1)

    complete_pattern = f"{type_pattern}(\([\w\-]+\))?:\s.*"
    match = re.match(complete_pattern, commit_message)
    if not match:
        print(error_message_incorrect_structure)
        exit(1)


if __name__ == "__main__":
    main()
`)


def main [
  path: path # Path to directory containing a Git repository.
] {
  let git_path = ($path | path join .git)
  if ($git_path | path type) != dir {
    return (error make {msg: $"($path) is not a Git repository. Exiting."})
  }
  
  let git_commit_msg_hook_path = ($git_path | path join hooks commit-msg)
  
  print $"Installing `commit-msg` hook script to repository @ ($path)..."
  if ($git_commit_msg_hook_path | path exists) {
    print "Overwriting existing commit-msg hook..."
  }
  
  $git_commit_msg_hook | save --force $git_commit_msg_hook_path
  chmod +x $git_commit_msg_hook_path
}
