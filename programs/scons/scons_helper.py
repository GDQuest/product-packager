import fileinput
import subprocess
from pathlib import Path
from typing import Tuple

import colorama

import add_node_icons
import highlight_code as highlighter
import table_of_contents

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
    projects = [
        p.parent.as_posix() for p in Path(root_dir).glob("./**/project.godot")
    ]
    return projects


def glob_extensions(root_path: Path, extensions: list) -> list:
    """Return all files in the given path with an extension in the extension list."""
    results = []
    for extension in extensions:
        results.extend(root_path.glob("**/" + extension))
    return results


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


def process_markdown_file_in_place(target, source, env):
    """A SCons Builder script, builds a markdown file into a rendered html file."""
    file_path = source[0].abspath
    content: str = ""
    with open(file_path, "r") as document:
        content = document.read()
    if content == "":
        print_error("Couldn't open file {}".format(file_path))
    content = add_node_icons.add_built_in_icons(content)
    content = table_of_contents.replace_contents_template(content)
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


def build_chapter_md(target, source, env):
    """A SCons Builder script"""
    source.sort()
    source_files = []
    for s in source:
        out = subprocess.run(
            ["pandoc", "-s", s.abspath, "--shift-heading-level-by=1", "-o", s.abspath],
            capture_output=True,
        )
        if out.returncode != 0:
            print_error(out.stderr.decode())
            raise Exception(out.stderr.decode())
        print_success(out.stdout.decode())
        source_files.append(s.abspath)
    target_path = Path(target[0].abspath).stem
    with open(target[0].abspath, "w") as fout:
        fout.write("# " + target_path + "\n")
        for line in fileinput.input(files=source_files):
            fout.write(line)

    return None


def get_epub_metadata(root_path: str) -> Tuple[str, str]:
    """Verify all epub settings files are present and return their paths"""
    root = Path(root_path)
    assert (root / "epub_metadata").exists()
    assert (root / "epub_metadata" / "metadata.txt").exists()
    assert (root / "epub_metadata" / "cover.png").exists()
    return (
        (root / "epub_metadata" / "metadata.txt").as_posix(),
        (root / "epub_metadata" / "cover.png").as_posix(),
    )


def get_epub_css() -> str:
    relative_path = Path("css/pandoc_epub.css")
    return relative_path.absolute().as_posix()


def get_gd_script_syntax() -> str:
    relative_path = Path("gd-script.xml")
    return relative_path.absolute().as_posix()


def get_gd_theme() -> str:
    relative_path = Path("gdscript.theme")
    return relative_path.absolute().as_posix()


def capture_book_title(metadata_path: str) -> str:
    """Read the book title from the metadata file to use as the filename."""
    metadata_file = Path(metadata_path)
    prefix = "title: "
    with open(metadata_file, "r") as read_obj:
        for line in read_obj:
            if line.startswith(prefix):
                book_name = line.lstrip(prefix)
                return "".join(x for x in book_name if x.isalnum()) + ".epub"
    raise Exception("missing project name")


def convert_to_epub(target, source, env):
    """Build epub file from installed sources."""
    md_files = []
    for file in env["installed_md_files"]:
        path = Path(file[0].abspath).relative_to(
            Path(env["BUILD_DIR"]).absolute()
        )
        md_files.append(path)
    out = subprocess.run(
        ["pandoc", "-o", env["EPUB_NAME"], "metadata.txt"]
        + md_files
        + [
            "--toc",
            "--syntax-definition",
            "gd-script.xml",
            "--highlight-style",
            "gdscript.theme",
        ],
        cwd=env["BUILD_DIR"],
        capture_output=True,
    )
    if out.returncode != 0:
        print_error(out.stderr.decode())
        raise Exception(out.stderr.decode())
    print_success(out.stdout.decode())


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
