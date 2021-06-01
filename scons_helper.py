import pathlib
from programs import highlight_code as highlighter
import subprocess
import colorama


colorama.init(autoreset=True)


def validate_source_dir(source_dir: str) -> bool:
    """Returns whether the directory contains a content folder"""
    source = pathlib.Path(source_dir)
    return (source / "content").exists()


def content_introspection(source_dir: str) -> list:
    """Returns a list of folders within the content folder"""
    assert (validate_source_dir(source_dir))
    source = pathlib.Path(source_dir)
    content = source / "content"
    content_folders = []
    for folder in content.iterdir():
        if folder.is_dir():
            content_folders.append(folder)
    return content_folders


def get_godot_folders(root_dir: str) -> list:
    """Return a list of all folders containing a project.godot file"""
    projects = [p.parent.as_posix() for p in pathlib.Path(root_dir).parent.glob("**/project.godot")]
    return projects


def glob_extensions(root_path: pathlib.Path, extensions: list) -> list:
    """Return all files in the given path with an extension in the extension list."""
    results = []
    for extension in extensions:
        results.extend(root_path.glob("**/" + extension))
    return results


def extension_to_html(filename: str) -> str:
    """Change the extension of a given filename to .html"""
    file_base = pathlib.Path(filename)
    file_base = file_base.as_posix().removesuffix(file_base.suffix)
    return pathlib.Path(file_base + ".html").as_posix()


def get_godot_filename(project_folder: str) -> str:
    """Return the project name from a directory with a project.godot file."""
    project_settings = pathlib.Path(project_folder) / "project.godot"
    prefix = "config/name="
    with open(project_settings, 'r') as read_obj:
        for line in read_obj:
            if line.startswith(prefix):
                return line.lstrip(prefix).replace(" ", "_").replace('"', '').replace('\n', '')
    raise Exception("missing project name")


def bundle_godot_project(target, source, env):
    """A SCons Builder script, builds a godot project directory into a zip file"""
    s = pathlib.Path(target[0].abspath)
    t = source[0].abspath
    gdname = s.stem
    success_log("Building project %s" % gdname)
    out = subprocess.run(["./package_godot_projects.sh", "-t", gdname, t, pathlib.Path(s).parent], cwd="./programs", capture_output=True)
    if out.returncode != 0:
        err_log(out.stderr.decode())
        raise Exception(out.stderr.decode())
    if "Done." in out.stdout.decode().split("\n"):
        success_log("%s built successfully." % gdname)
    return None


def process_markdown_file_in_place(target, source, env):
    """A SCons Builder script, builds a markdown file into a rendered html file."""
    filename = source[0].abspath
    content = highlighter.highlight_code_blocks(filename)
    with open(filename, "w") as document:
        document.write(content)

    out = subprocess.run(["./convert_markdown.sh", "-c", "css/pandoc.css", "-o", "../", filename], cwd="./programs", capture_output=True)

    if out.returncode != 0:
        err_log(out.stderr.decode())
        raise Exception(out.stderr.decode())
    success_log(out.stdout.decode())

    remove_figcaption(pathlib.Path(target[0].abspath))

    return None


def remove_figcaption(html_path: pathlib.Path):
    out = subprocess.run(["sed -Ei 's|<figcaption>.+</figcaption>||' " + html_path.as_posix()], capture_output=True,
                         shell=True)
    success_log(out.stdout.decode())
    err_log(out.stderr.decode())


def success_log(log_message: str):
    print(colorama.Fore.GREEN + log_message)


def err_log(log_message: str):
    print(colorama.Fore.RED + log_message)