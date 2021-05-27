import pathlib


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
