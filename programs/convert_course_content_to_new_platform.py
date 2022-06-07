"""Converts the content directory to the format of the new course platform.

Temporary script done in Python for speed to allow building the minimum viable
product.

Todo:

- Remove the {=html} stuff added by pandoc, just have valid markdown, <svg/>
  tags are okay.

- Port to nim

- Output files to dist dir (use nim build sys as a base as it already does that)

- Convert link shortcodes e.g. {{ link learn-to-code-how-to-install-godot How to
  download and run Godot }} to [How to download and run
  Godot](/course/learn-to-code-from-zero-with-godot/introduction/learn-to-code-how-to-install-godot)

- Replace all shortcodes with nim

"""

import re
import yaml
import os
import sys

HELP_MESSAGE = """
Converts a folder containing markdown files *IN-PLACE* to work with the new web platform.

USAGE: convert-to-new-platform.py CONTENT_DIRECTORY

For each content markdown file:

- Converts image paths from relative to absolute.
- Adds yaml front matter to the file.

For each section folder:

- Creates a file named _index.md with yaml metadata.
"""


def to_slug(file_name: str) -> str:
    """Convert a file name to a page slug."""
    file_name = re.sub(r"\d+\.", "", file_name)
    if file_name.endswith(".md"):
        file_name = os.path.splitext(file_name)[0]
    file_name = file_name.replace(" ", "-")
    return file_name


def generate_yaml_front_matter(content: str, file_path: str) -> str:
    """Return a YAML string to append at the start of a content file."""

    def get_title(content: str) -> str:
        match = re.search(r"^# (.+)$", content, flags=re.MULTILINE)
        if not match:
            raise ValueError(
                f"The file {file_path} does not have an H1 title."
                " We need one to generate the YAML front matter."
            )
        return match.group(1).capitalize()

    data = {
        "title": get_title(content),
        "slug": to_slug(os.path.basename(file_path)),
        "draft": False,
        "free": False,
    }
    return f"---\n{yaml.dump(data)}---"


def convert_image_paths_to_absolute(content: str, content_dir: str, slug: str) -> str:
    """Replace relative image paths in the content with absolute output paths."""
    dirpath, dirname = os.path.split(content_dir)
    section_slug = to_slug(dirname)
    output_dir = os.path.join(
        "/courses/learn-to-code-from-zero", section_slug, "images"
    )

    def make_image_absolute(match: re.Match):
        alt = match.group(1)
        file_name = os.path.basename(match.group(2))
        abs_path = os.path.join(output_dir, file_name)
        return f"![{alt}]({abs_path})"

    return re.sub(r"\!\[(.*?)\]\((.*?)\)", make_image_absolute, content)


def generate_section_info(folder_path: str) -> None:
    """Create and fills an _index.md file for a given folder."""

    def folder_to_title(folder_name: str) -> str:
        folder_name = re.sub(r"\d*\.", "", folder_name)
        return folder_name.replace("-", " ").capitalize()

    output_path = os.path.join(folder_path, "_index.md")
    with open(output_path, "w") as f:
        folder_name = os.path.basename(folder_path)
        data = {
            "title": folder_to_title(folder_name),
            "slug": to_slug(folder_name),
        }
        f.write(f"---\n{yaml.dump(data)}---")


def replace_shortcodes(content: str) -> str:
    """Replace {{}} shortcodes.

    Function to replace the shortcodes and avoid build errors until we have the
    time to port the code to Nim.

    """
    return re.sub(r"{{.+}}", "SHORTCODE_PLACEHOLDER", content)


def main():
    """Find and convert markdown files."""
    argv = sys.argv[1:]
    if not argv or argv[0] in ["-h", "--help"]:
        print(HELP_MESSAGE)

    folder_path = argv[0]
    if not os.path.isdir(folder_path):
        raise ValueError(
            "The program needs a valid folder path to work with. Call convert-to-new-platform.py --help for usage information."
        )

    # Find all content markdown files and replace stuff in each.
    markdown_file_paths = [
        os.path.join(folder, f)
        for folder, _, files in os.walk(folder_path)
        for f in files
        if f.endswith(".md") and f != "_index.md"
    ]
    for file_path in markdown_file_paths:
        with open(file_path, "r") as f:
            content = f.read()
            file_name = os.path.basename(file_path)
            directory = os.path.dirname(file_path)
            slug = to_slug(file_name)
            content = convert_image_paths_to_absolute(content, directory, slug)
            content = replace_shortcodes(content)
            content = re.sub(r"<!--.*?-->", "", content)
            front_matter = generate_yaml_front_matter(content, file_path)

        with open(file_path, "w") as f:
            f.write(front_matter + "\n" + content)

    # Generate _index.md files in each section
    for name in os.listdir(folder_path):
        path = os.path.join(folder_path, name)
        if os.path.isdir(path):
            generate_section_info(path)


if __name__ == "__main__":
    main()
