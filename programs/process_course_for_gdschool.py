"""Process and output the files of a course from Mavenseed to GDSchool"""


import argparse
from dataclasses import dataclass
import os
import shutil
import subprocess


THIS_DIRECTORY = os.path.dirname(os.path.realpath(__file__))
CONVERT_COURSE_CONTENT_SCRIPT_PATH = os.path.join(
    THIS_DIRECTORY, "convert_course_content_to_new_platform.py"
)


@dataclass
class Args:
    """Command-line arguments"""

    input_directory_path: str
    gdschool_repository_path: str


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "input_directory_path",
        type=str,
        help="Path to the directory containing the files to process",
    )
    parser.add_argument(
        "gdschool_repository_path",
        type=str,
        help="Path to the GDSchool repository",
    )
    parsed = parser.parse_args()
    args = Args(
        input_directory_path=os.path.abspath(parsed.input_directory_path),
        gdschool_repository_path=os.path.abspath(parsed.gdschool_repository_path),
    )

    if not os.path.exists(args.gdschool_repository_path):
        raise FileNotFoundError(
            f"The GDSchool repository path {args.gdschool_repository_path} does not exist"
        )
    if not os.path.exists(args.input_directory_path):
        raise FileNotFoundError(
            f"The input directory path {args.input_directory_path} does not exist"
        )

    converted_content_directory = os.path.join("converted_content", "courses", os.path.basename(args.input_directory_path))
    convert_command = [
        "python3",
        CONVERT_COURSE_CONTENT_SCRIPT_PATH,
        ".",
        converted_content_directory,
    ]
    nim_preprocessor_command = ["preprocessgdschool", "--course-dir:converted_content"]
    print(f"Executing: {' '.join(convert_command)}")

    # Convert content, then preprocess using the nim preprocessor
    subprocess.run(convert_command, cwd=args.input_directory_path)
    subprocess.run(nim_preprocessor_command, cwd=args.input_directory_path)

    # # Copy files to GDSchool
    gdschool_target_directory = os.path.join(args.gdschool_repository_path, "markdown", "courses", os.path.basename(args.input_directory_path))
    if os.path.exists(gdschool_target_directory):
        shutil.rmtree(gdschool_target_directory)
    output = shutil.copytree(os.path.join(args.input_directory_path, converted_content_directory), gdschool_target_directory)

    # Rename output directory to course name
    os.rename(output, os.path.join(gdschool_target_directory, os.path.basename(args.input_directory_path)))

if __name__ == "__main__":
    main()
