import subprocess
import sys
from pathlib import Path
from typing import List

import colorama
from SCons.Script import Dir, File


def get_godot_project_files(dir: Dir, ignore_directories: List[str] = []) -> list[Path]:
    """Return a list of all folders containing a project.godot file"""
    directory: Path = Path(str(dir))
    subdirectories: List[Path] = [
        Path(str(d))
        for d in directory.iterdir()
        if d.is_dir() and not d.name in ignore_directories and not d.name.startswith(".")
    ]
    return [
        p for d in subdirectories for p in d.glob("**/project.godot")
    ]


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


def calculate_target_file_paths(
    destination: Dir, relative_dir: Dir, source_files: list[File]
) -> list[File]:
    """Returns the list of files taking their path from relative_dir and
    appending it to destination."""
    return [
        File(Path(str(sf)).relative_to(str(relative_dir)), directory=destination)
        for sf in source_files
    ]


def print_success(*args, **kwargs):
    print(colorama.Fore.GREEN, end="", flush=True)
    print(*args, **kwargs)
    print(colorama.Fore.RESET, end="", flush=True)


def print_error(*args, **kwargs):
    print(colorama.Fore.RED, end="", flush=True)
    print(*args, file=sys.stderr, **kwargs)
    print(colorama.Fore.RESET, end="", flush=True)
