import pathlib
from programs import highlight_code as highlighter
import subprocess
import colorama


def validate_source_dir(source_dir: str) -> bool:
    source = pathlib.Path(source_dir)
    return (source / "content").exists()


def content_introspection(source_dir: str) -> list:
    source = pathlib.Path(source_dir)
    content = source / "content"
    assert(content.exists())
    content_folders = []
    for folder in content.iterdir():
        if folder.is_dir():
            content_folders.append(folder)
    return content_folders


def capture_folder(root_path: pathlib.Path, folder_name: str, extensions: list) -> list:
    folder = root_path / folder_name
    results = []
    if not folder.exists():
        return results
    for extension in extensions:
        results.extend(folder.glob(extension))
    return results


def glob_extensions(root_path: pathlib.Path, extensions: list) -> list:
    results = []
    for extension in extensions:
        results.extend(root_path.glob("**/" + extension))
    return results


def extension_to_html(filename: str) -> str:
    file_base = pathlib.Path(filename)
    file_base = file_base.as_posix().removesuffix(file_base.suffix)
    return pathlib.Path(file_base + ".html").as_posix()


def process_markdown_file_in_place(target, source, env):
    # apply highlighting
    filename = source
    content = highlighter.highlight_code_blocks(filename)
    with open(filename, "w") as document:
        document.write(content)
    # convert to html
    colorama.init(autoreset=True)
    out = subprocess.run(["./convert_markdown.sh", "-c", "css/pandoc.css", "-o", "../", "../" + filename], cwd="./programs", capture_output=True)
    if out.returncode != 0:
        err_log(out.stderr.decode())
        raise Exception(out.stderr.decode())
    success_log(out.stdout.decode())
    #
    file_base = pathlib.Path(filename)
    # # strip the suffix from the path
    file_base = file_base.as_posix().removesuffix(file_base.suffix)
    html_path = pathlib.Path(target)
    if html_path.exists():
        success_log("removing original markdown file")
        # pathlib.Path(filename).unlink()
        return None
    else:
        err_log("unsuccessful markdown conversion")
        return 1
        # raise Exception("unsuccessful markdown conversion")
    #     # TODO: we should error out now

    remove_figcaption(html_path)


def remove_figcaption(html_path: pathlib.Path):
    out = subprocess.run(["sed -Ei 's|<figcaption>.+</figcaption>||' " + html_path.as_posix()], capture_output=True,
                         shell=True)
    success_log(out.stdout.decode())
    err_log(out.stderr.decode())

def success_log(log_message):
    print(colorama.Fore.GREEN + log_message)


def err_log(log_message):
    print(colorama.Fore.RED + log_message)