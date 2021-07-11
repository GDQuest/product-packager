import subprocess
from pathlib import Path

import colorama

colorama.init(autoreset=True)
cwd_base = Path(__file__).parent.absolute().as_posix()


def validate_git_version(source_dir: str) -> bool:
    """Compares git release tags, of root and godot projects to make sure they are identical"""
    godot_projects = get_godot_folders(source_dir)
    godot_projects.append(source_dir)
    result_set = {}
    for item in godot_projects:
        out = subprocess.run(
            ["git", "describe", "--tags"], capture_output=True, cwd=item
        )
        if out.returncode != 0:
            print_error(out.stderr.decode())
            raise Exception(out.stderr.decode())
        result_set[Path(item).name] = out.stdout.decode().strip()
    if len(set(result_set.values())) == 1:
        # All git versions match
        return True
    print_error("Multiple git release tags found")
    for key, value in result_set.items():
        print_error(key + " : " + value)
    return False


def is_source_directory_valid(source_dir: str) -> bool:
    """Returns whether the directory contains a content folder"""
    content_directory = Path(source_dir) / "content"
    return content_directory.is_dir()


def content_introspection(source_dir: str) -> list:
    """Returns a list of folders within the content folder"""
    assert (
        is_source_directory_valid(source_dir),
        "Source directory lacks a content/ subdirectory.",
    )
    content_directory = Path(source_dir) / "content"
    return [folder for folder in content_directory.iterdir() if folder.is_dir()]


def get_godot_folders(root_dir: str) -> list:
    """Return a list of all folders containing a project.godot file"""
    projects = [p.parent.as_posix() for p in Path(root_dir).glob("**/project.godot")]
    return projects


def bundle_godot_project(target, source, env):
    """A SCons Builder script, builds a godot project directory into a zip file"""
    zipfile_path = Path(target[0].abspath)
    target_directory = zipfile_path.parent
    godot_project_directory = Path(source[0].abspath).parent
    godot_project_name = zipfile_path.stem
    print_success("Building project %s" % godot_project_name)

    out = subprocess.run(
        [
            "./package_godot_project.py",
            godot_project_directory,
            "--output",
            target_directory,
            "--title",
            godot_project_name,
        ],
        capture_output=True,
        cwd=cwd_base,
    )
    if out.returncode != 0:
        print_error(out.stderr.decode())
        raise Exception(out.stderr.decode())
    if "Done." in out.stdout.decode().split("\n"):
        print_success("%s built successfully." % godot_project_name)
    return None


def print_success(log_message: str):
    print(colorama.Fore.GREEN + log_message)


def print_error(log_message: str):
    print(colorama.Fore.RED + log_message)
