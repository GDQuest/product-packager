import pathlib
from programs import highlight_code as highlighter
import subprocess
import colorama
import fileinput
from panflute import run_filter, Header


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
    projects = [p.parent.as_posix() for p in pathlib.Path(root_dir).glob("./**/project.godot")]
    return projects


def glob_extensions(root_path: pathlib.Path, extensions: list) -> list:
    """Return all files in the given path with an extension in the extension list."""
    results = []
    for extension in extensions:
        results.extend(root_path.glob("**/" + extension))
    return results


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
    file_parent = pathlib.Path(filename).parent.as_posix()
    #TODO: "../build" replace this with a dynamic path! "../" + env["BUILD"] this is broken
    out = subprocess.run(["./convert_markdown.sh", "-c", "css/pandoc.css", "-o", "../" , filename], cwd="./programs", capture_output=True)

    if out.returncode != 0:
        err_log(out.stderr.decode())
        raise Exception(out.stderr.decode())
    success_log(out.stdout.decode())

    remove_figcaption(pathlib.Path(target[0].abspath))

    return None


def increase_header_level(elem, doc):
    if type(elem)==Header:
        if elem.level < 6:
            elem.level += 1
        else:
            return []


def run_pandoc_filter(doc):
    return run_filter(increase_header_level, doc=doc)


def build_chapter_md(target, source, env):
    """A SCons Builder script"""
    source.sort()
    source_files = []
    for s in source:
        out = subprocess.run(
            ["pandoc", "-s", s.abspath, "--filter", "programs/filter.py", "-o", s.abspath], capture_output=True)
        if out.returncode != 0:
            err_log(out.stderr.decode())
            raise Exception(out.stderr.decode())
        success_log(out.stdout.decode())
        source_files.append(s.abspath)
    target_path = pathlib.Path(target[0].abspath).stem
    with open(target[0].abspath, 'w') as fout:
        fout.write("# " + target_path + "\n")
        for line in fileinput.input(files=source_files):
            fout.write(line)

    return None


def get_epub_metadata(root_path: str) -> tuple[str, str]:
    root = pathlib.Path(root_path)
    assert(root / "epub_metadata").exists()
    assert (root / "epub_metadata" / "metadata.txt").exists()
    assert (root / "epub_metadata" / "cover.png").exists()
    return (root / "epub_metadata" / "metadata.txt").as_posix(), (root / "epub_metadata" / "cover.png").as_posix()


def get_epub_css():
    relative_path = pathlib.Path("programs/css/pandoc.css")
    return relative_path.absolute().as_posix()


def convert_to_epub(target, source, env):
    md_files = []
    for file in env["installed_md_files"]:
        md_files.append(pathlib.Path(file[0].abspath).relative_to(pathlib.Path(env["BUILD_DIR"]).absolute()))
    # for the title you need a metadata.text file
    # pass in all the files to the book, they need to be ordered
    # how do chapters and the contenst work
    # generate a title
    # css works but isn't being passed in...
    err_log("BUILD")
    out = subprocess.run(["pandoc", "-o", "thebook.epub", "metadata.txt"] + md_files + ["--css", "pandoc.css", "--toc"], cwd=env["BUILD_DIR"], capture_output=True)
    if out.returncode != 0:
        err_log(out.stderr.decode())
        raise Exception(out.stderr.decode())
    success_log(out.stdout.decode())


def remove_figcaption(html_path: pathlib.Path):
    out = subprocess.run(["sed -Ei 's|<figcaption>.+</figcaption>||' " + html_path.as_posix()], capture_output=True,
                         shell=True)
    success_log(out.stdout.decode())
    err_log(out.stderr.decode())


def success_log(log_message: str):
    print(colorama.Fore.GREEN + log_message)


def err_log(log_message: str):
    print(colorama.Fore.RED + log_message)