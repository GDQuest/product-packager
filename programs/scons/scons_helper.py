import fileinput
import subprocess
from pathlib import Path
from typing import Tuple, List

import colorama

import add_node_icons
import highlight_code as highlighter
import table_of_contents
import include
import link

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


def validate_source_dir(source_dir: str) -> bool:
    """Returns whether the directory contains a content folder"""
    source = Path(source_dir)
    return (source / "content").exists()


def content_introspection(source_dir: str) -> list:
    """Returns a list of folders within the content folder"""
    assert validate_source_dir(source_dir)
    source = Path(source_dir)
    content = source / "content"
    content_folders = []
    for folder in content.iterdir():
        if folder.is_dir():
            content_folders.append(folder)
    return content_folders


def get_godot_folders(root_dir: str) -> list:
    """Return a list of all folders containing a project.godot file"""
    projects = [p.parent.as_posix() for p in Path(root_dir).glob("./**/project.godot")]
    return projects


def get_godot_filename(project_folder: str) -> str:
    """Return the project name from a directory with a project.godot file."""
    project_settings = Path(project_folder) / "project.godot"
    prefix = "config/name="
    with open(project_settings, "r") as read_obj:
        for line in read_obj:
            if line.startswith(prefix):
                return (
                    line.lstrip(prefix)
                    .replace(" ", "_")
                    .replace('"', "")
                    .replace("\n", "")
                )
    raise Exception("missing project name")


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


def build_cheatsheet(target, source, env):
    """A SCons Builder script, generates a cheatsheet, using a python file in the target directory"""
    cheat_path = Path(env["src"]) / Path("content")
    out = subprocess.run(
        ["./generate_cheatsheet.py", ".", "../dist"],
        capture_output=True,
        cwd=cheat_path,
    )
    if out.returncode != 0:
        print_error(out.stderr.decode())
        raise Exception(out.stderr.decode())
    else:
        print_success("cheatsheet built successfully.")
    return None


def process_markdown_file_in_place(target, source, env):
    """A SCons Builder script, builds a markdown file into a rendered html file."""
    file_path: Path = Path(source[0].abspath)
    content: str = ""
    with open(file_path, "r") as document:
        content = document.read()

    if content == "":
        print_error("Couldn't open file {}".format(file_path.as_posix()))

    content = include.process_document(content, file_path)
    content = link.process_document(content, file_path)
    content = table_of_contents.replace_contents_template(content)
    content = add_node_icons.add_built_in_icons(content)
    content = highlighter.highlight_code_blocks(content)
    with open(file_path, "w") as document:
        document.write(content)

    out = subprocess.run(
        [
            "./convert_markdown.py",
            file_path,
            "--output-directory",
            env["BUILD_DIR"],
        ],
        capture_output=True,
        cwd=cwd_base,
    )

    if out.returncode != 0:
        print_error(out.stderr.decode())
        raise Exception(out.stderr.decode())

    remove_figcaption(Path(target[0].abspath))
    return None


def remove_figcaption(html_path: Path):
    """A cleanup step for generated md files."""
    out = subprocess.run(
        ["sed -Ei 's|<figcaption>.+</figcaption>||' " + html_path.as_posix()],
        capture_output=True,
        shell=True,
    )
    if out.returncode != 0:
        print_error(out.stderr.decode())


def print_success(log_message: str):
    print(colorama.Fore.GREEN + log_message)


def print_error(log_message: str):
    print(colorama.Fore.RED + log_message)
