"""Converts the content folder to the format of the new course platform.

Temporary script done in Python for speed to allow building the minimum viable
product.
"""

from dataclasses import dataclass
import re
import yaml
import os
from enum import Enum
import argparse
import shutil


class ContentType(Enum):
    POST = 1
    PAGE = 2
    LESSON = 3


FOLDER_TO_CONTENT_TYPE = {
    "posts": ContentType.POST,
    "courses": ContentType.LESSON,
    "pages": ContentType.PAGE,
}


@dataclass
class Args:
    """Represents the command line arguments"""

    input_folder: str
    output_folder: str
    repository_name: str

    @staticmethod
    def test_and_get_command_line_arguments() -> "Args":
        parser = argparse.ArgumentParser(
            description="Converts a folder containing markdown files *IN-PLACE* to work with the new web platform. "
            "USAGE: convert-to-new-platform.py CONTENT_folder /"
            "For each content markdown file, adds yaml front matter to the file. "
            "For each section folder, creates a file named _index.md with yaml metadata."
        )
        parser.add_argument(
            "input_folder",
            type=str,
            help="Path to the repository containing the content. Default: './'",
            default=".",
        )
        parser.add_argument(
            "output_folder",
            type=str,
            help="Path to the output folder. Default: 'dist/'",
            default="dist",
        )
        args = parser.parse_args()
        # Test the validity of the arguments
        if not os.path.isdir(args.input_folder):
            raise ValueError(
                "The program needs a valid folder path to work with. Call convert-to-new-platform.py --help for usage information."
            )
        if not os.path.exists(os.path.join(args.input_folder, ".git")):
            raise Exception(
                f"The repository path {args.input_folder} does not have a .git/ folder. Is the path correct? Courses should be part of a Git repository."
            )
        content_folder = os.path.join(args.input_folder, "content")
        if not os.path.isdir(content_folder):
            raise Exception(
                f"The course repository path {args.input_folder} does not have a content/ folder. The script can't find content files."
            )
        return Args(
            input_folder=args.input_folder,
            output_folder=args.output_folder,
            repository_name=os.path.basename(args.input_folder),
        )


def get_content_type(file_path: str) -> ContentType:
    for folder_name in FOLDER_TO_CONTENT_TYPE.keys():
        if folder_name + "/" in file_path:
            return FOLDER_TO_CONTENT_TYPE[folder_name]
    return None


def process_website_content_files(args: Args):
    raise NotImplementedError(
        "Processing website files isn't complete yet as we decided to only "
        "publish courses on GDSchool for now. "
        "Please use this script only on Godot course repositories."
    )

    # TODO: move/copy website files to new folder structure, then we iterate over files there to replace them
    # TODO: first copy the files to dist, then process those files in place
    # TODO: write down move rules and redirects
    # We make one repo with posts/, bundles/, and pages/ dirs
    # FOR WEBSITE ONLY:
    # tutorials/$year/$slug/index.md
    # archives/$year/$slug/index.md
    # tools/$year/$slug/index.md
    # articles/$year/$slug/index.md -> blog posts
    # images go in images/ subfolder
    # Thumbnail/banner image is images/thumbnail.png

    content_folder = os.path.join(args.input_folder, "content")
    markdown_file_paths = Utils.find_all_markdown_files(content_folder)

    # Replace markdown content in-place in markdown files copied over to args.output_folder
    REPLACE_PAIRS = {
        r"{{< note >}}": '<Callout title="Note">',
        r"{{< /note >}}": "</Callout>",
        r"{{% note %}}": '<Callout title="Note">',
        r"{{% /note %}}": "</Callout>",
        r"{{% warning %}}": '<Callout title="Warning">',
        r"{{% /warning %}}": "</Callout>",
    }

    markdown_file_paths = Utils.find_all_markdown_files(args.output_folder)
    for path in markdown_file_paths:
        with open(path) as markdown_file:
            content = markdown_file.read()
            for source, replacement in REPLACE_PAIRS:
                content = content.replace(source, replacement)
            content = Utils.find_and_replace_shortcodes(content, args, path)
            with open(path, "w") as markdown_file:
                markdown_file.write(content)


def process_course_content_files(args: Args):
    course_path = args.input_folder
    if not os.path.exists(os.path.join(course_path, ".git")):
        raise Exception(
            f"The course repository path {course_path} does not have a .git/ folder. Is the path correct? Courses should be part of a Git repository."
        )
    content_folder = os.path.join(course_path, "content")
    if not os.path.exists(content_folder):
        raise Exception(
            f"The course repository path {course_path} does not have a content/ folder. The script can't find content files."
        )

    markdown_file_paths = Utils.find_all_markdown_files(content_folder)
    print(f"Processing {len(markdown_file_paths)} markdown files.")
    created_markdown_files = []
    for path in markdown_file_paths:
        slug = os.path.basename(path)
        chapter_dir = os.path.basename(os.path.dirname(path))
        target_markdown_file = os.path.join(args.output_folder, chapter_dir, slug)
        new_file_path = Utils.copy_markdown_file_and_dependencies(
            path, target_markdown_file
        )
        created_markdown_files.append(new_file_path)
        print(new_file_path)

    # Process newly created markdown files in place
    for file_path in created_markdown_files:
        content_type = get_content_type(file_path)
        with open(file_path, "r") as f:
            content = f.read()
            content = re.sub(r"<!--.*?-->", "", content)
            front_matter = Utils.generate_yaml_front_matter(
                content, file_path, content_type
            )
            content = Utils.find_and_replace_shortcodes(content, args, file_path)
            # FIXME: Test if this works
            with open(file_path, "w") as f:
                f.write(front_matter + "\n" + content)

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
                "slug": Utils.to_slug(folder_name),
            }
            f.write(f"---\n{yaml.dump(data)}---")

    for name in os.listdir(args.output_folder):
        path = os.path.join(args.output_folder, name)
        if os.path.isdir(path):
            generate_section_info(path)


class Utils:
    @staticmethod
    def find_all_markdown_files(content_folder: str) -> list:
        return [
            os.path.join(folder, f)
            for folder, _, files in os.walk(content_folder)
            for f in files
            if f.endswith(".md")
        ]

    @staticmethod
    def to_slug(file_name: str) -> str:
        """Convert a file name to a page slug."""
        file_name = re.sub(r"\d+\.", "", file_name)
        if file_name.endswith(".md"):
            file_name = os.path.splitext(file_name)[0]
        file_name = file_name.replace(" ", "-")
        return file_name

    @staticmethod
    def generate_yaml_front_matter(
        content: str, file_path: str, content_type: ContentType
    ) -> str:
        """Return a YAML string to append at the start of a content file."""

        def parse_yaml_front_matter(content: str) -> dict:
            frontmatter_re = re.compile(r"---\n(.*?)\n---\n", re.DOTALL)
            match: re.Match = frontmatter_re.match(content)
            if match:
                try:
                    return yaml.safe_load(match.group(1))
                except yaml.YAMLError:
                    print("Failed to parse front matter: %s" % match.group(1))
            return {}

        def get_title(content: str) -> str:
            match = re.search(r"^# (.+)$", content, flags=re.MULTILINE)
            if not match:
                raise ValueError(
                    f"The file {file_path} does not have an H1 title."
                    " We need one to generate the YAML front matter."
                )
            return match.group(1).capitalize()

        existing_data = parse_yaml_front_matter(content)
        data = {}
        data["draft"] = existing_data.get("draft", False)
        data["description"] = existing_data.get("description", "")
        data["title"] = (
            existing_data["title"] if "title" in existing_data else get_title(content)
        )
        data["slug"] = (
            existing_data["slug"]
            if "slug" in existing_data
            else Utils.to_slug(os.path.basename(os.path.dirname(file_path)))
        )

        if content_type == ContentType.LESSON:
            data["free"] = False
        elif content_type == ContentType.POST:
            data["tags"] = []
            data["relatedPosts"] = []
            data["difficulty"] = 2
            data["order"] = 5
            data["redirects"] = existing_data.get("redirects", [])
            data["thumbnail"] = ""
            # Get banner image from hugo frontmatter. Old posts have a hardcoded
            # banner path, newer pages use the resource system.
            if "banner" in existing_data and "src" in existing_data["banner"]:
                data["thumbnail"] = existing_data["banner"]["src"]
            elif "resources" in existing_data:
                for resource in existing_data["resources"]:
                    if "src" in resource:
                        data["thumbnail"] = resource["src"]
                        break
        elif content_type == ContentType.PAGE:
            data["social"] = ""
        return f"---\n{yaml.dump(data)}---"

    @staticmethod
    def find_and_replace_shortcodes(content: str, args: Args, markdown_file_path: str):
        """
        Find and replace shortcodes in each line in content. Shortcodes have the
        form {{ shortcode }} or {{< shortcode >}} They can be on multiple lines
        too."""
        SHORTCODE_REGEX = re.compile(r"{+[<%]?\s*([a-zA-Z0-9\-_\. ]+)\s*[>%]?}+")
        output = []
        for line in content.splitlines():
            match = SHORTCODE_REGEX.search(line)
            if match:
                split_shortcode = match.group(1).split(" ")
                shortcode_name, shortcode_args = split_shortcode[0], split_shortcode[1:]
                if shortcode_name == "link":
                    target = shortcode_args[0]
                    description = " ".join((arg for arg in shortcode_args[1:])).strip()
                    if description == "":
                        description = target
                    # Path is relative, we need to make it absolute
                    # TODO: needs to account for current folder though
                    if os.path.basename(target) == target:
                        if target.endswith(".md"):
                            target = target.replace(".md", "")
                        url = "/" + os.path.relpath(
                            os.path.dirname(markdown_file_path), args.input_folder
                        )
                        target = os.path.join(url, target)
                    line = line.replace(match.group(0), f"[{description}]({target})")
                elif shortcode_name == "calltoaction":
                    # TODO: only for gdquest.com, so can wait
                    url, text = ""
                    replacement = f'<Button cta centered href="{url}">{text}</Button>'
                    line = line.replace(match.group(0), replacement)
                # We remove tables of contents from node essentials
                elif shortcode_name == "contents":
                    continue
            output.append(line)
        return "\n".join(output)

    @staticmethod
    def copy_markdown_file_and_dependencies(
        markdown_file: str, target_path: str
    ) -> str:
        """
        Copies a markdown file to a target folder or markdown file path, along with its dependencies.
        Moves all media files to the target folder/images.

        Returns the path of the output markdown file.
        """
        input_folder = os.path.dirname(markdown_file)

        target_folder = output_markdown_path = target_path
        if target_path.endswith(".md"):
            target_folder = os.path.dirname(target_path)
        else:
            output_markdown_path = os.path.join(target_folder, "index.md")

        output_images_folder = os.path.join(target_folder, "images")
        if not os.path.exists(output_images_folder):
            os.makedirs(output_images_folder)

        # Copy files to output path
        MEDIA_FILE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".mp4")
        for folder, _, files in os.walk(input_folder):
            for file in files:
                file_path = os.path.join(folder, file)
                if os.path.splitext(file_path)[1] not in MEDIA_FILE_EXTENSIONS:
                    continue
                shutil.copy(file_path, os.path.join(output_images_folder, file))

        shutil.copy(markdown_file, output_markdown_path)

        # Replace all image paths in the markdown file with the images folder
        # NOTE: does not attempt to fix other shortcodes and special cases like LocalVideo
        def replace_image(match):
            alt = match.group(1)
            filename = os.path.basename(match.group(2))
            return f"![{alt}](images/{filename})"

        with open(output_markdown_path, "r", encoding="utf-8") as f:
            output_markdown = f.read()
            output_markdown = re.sub(
                r"!\[(.*?)\]\((.*?)\)", replace_image, output_markdown
            )
        with open(output_markdown_path, "w", encoding="utf-8") as f:
            f.write(output_markdown)

        return output_markdown_path


def main():
    """Find and convert markdown files."""

    args = Args.test_and_get_command_line_arguments()

    if not os.path.isdir(args.output_folder):
        print(f"Creating output folder: {args.output_folder}")
        os.makedirs(args.output_folder)

    is_website = args.input_folder.endswith("website") and os.path.exists(
        os.path.join(args.input_folder, "config.toml")
    )
    if is_website:
        print(
            f"The repository path {args.input_folder} is the GDQuest website. Processing files..."
        )
        process_website_content_files(args)
    else:
        print(
            f"The repository path {args.input_folder} is a course. Processing files..."
        )
        process_course_content_files(args)


if __name__ == "__main__":
    main()
