import subprocess
import sys
from pathlib import Path

import colorama
from SCons.Script import Dir, File


def get_godot_project_files(dir: Dir) -> list[File]:
    """Return a list of all folders containing a project.godot file"""
    return [File(p) for p in Path(str(dir)).glob("**/project.godot")]


def validate_git_versions(source_dir: Dir) -> bool:
    """Compares git release tags, of root and godot projects to make sure they are identical"""
    godot_project_dirs = [pf.Dir(".") for pf in get_godot_project_files(source_dir)]
    godot_project_dirs.append(source_dir)

    results = {}
    for godot_project_dir in godot_project_dirs:
        out = subprocess.run(
            ["git", "describe", "--tags"], capture_output=True, cwd=godot_project_dir
        )
        if out.returncode != 0:
            print_error(out.stderr.decode())
            raise Exception(out.stderr.decode())
        results[godot_project_dir.name] = out.stdout.decode().strip()

    ret = False
    if len(set(results.values())) == 1:
        # All git versions match
        ret = True

    print_error("WARNING: Multiple git release tags found!")
    for key, value in results.items():
        print_error(key + " : " + value)

    return ret


def print_success(*args, **kwargs):
    print(colorama.Fore.GREEN, end="", flush=True)
    print(*args, **kwargs)
    print(colorama.Fore.RESET, end="", flush=True)


def print_error(*args, **kwargs):
    print(colorama.Fore.RED, end="", flush=True)
    print(*args, file=sys.stderr, **kwargs)
    print(colorama.Fore.RESET, end="", flush=True)
