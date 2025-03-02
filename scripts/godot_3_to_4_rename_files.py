"""This script renames files in a Godot project to snake_case. It's used to update Godot 3 projects to Godot 4 conventions.

In Godot 3 we'd name files like `MyScene.tscn` and in Godot 4 we name them `my_scene.tscn`.

The script modifies:

- File and folder names
- Path attributes in .tscn and .tres files (references to other files)
- Preload calls in .gd files
- File paths in project.godot
"""
import argparse
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Config:
    dry_run: bool
    quiet: bool
    start_path: Path
    run_tests: bool = False
    process_addons: bool = False


def parse_args() -> Config:
    parser = argparse.ArgumentParser(
        description="Rename files in a Godot project to snake_case."
    )
    parser.add_argument(
        "--dry-run", "-d", action="store_true", help="Run without making changes"
    )
    parser.add_argument(
        "--quiet", "-q", action="store_true", help="Only print errors and debug"
    )
    parser.add_argument(
        "--path", "-p", type=Path, default=".", help="Starting path for renaming"
    )
    parser.add_argument(
        "--process-addons", "-a", action="store_true",
        help="Process files in the addons folder (by default, addons are skipped)"
    )
    parser.add_argument("--test", "-t", action="store_true", help="Run tests")

    args = parser.parse_args()

    if not args.path.exists():
        parser.error(f"Start path does not exist: {args.path}")

    return Config(
        dry_run=args.dry_run,
        quiet=args.quiet,
        start_path=args.path,
        run_tests=args.test,
        process_addons=args.process_addons,  # Add this line
    )


def to_snake_case(name: str) -> str:
    parts = name.split("/")
    converted_parts = []
    for part in parts:
        step_1 = re.sub(r"(\w)(\d+[a-zA-Z])", r"\1_\2", part)
        step_2 = re.sub(r"(.)(?<!_)([A-Z][a-z]+)", r"\1_\2", step_1)
        step_3 = re.sub(r"([a-z])(?<!_)([A-Z])", r"\1_\2", step_2)
        converted_parts.append(step_3.lower())
    return "/".join(converted_parts)


def update_file_content(
    file_path: Path, config: Config, regex_patterns: list[re.Pattern]
) -> None:
    with open(file_path, "r") as file:
        content = file.read()

    updated_content = content
    modified_attributes = []

    for regex_pattern in regex_patterns:
        updated_content = regex_pattern.sub(
            lambda m: m.group(0).replace(m.group(1), to_snake_case(m.group(1))),
            updated_content,
        )
        if config.dry_run:
            modified_attributes.extend(regex_pattern.findall(updated_content))

    if config.dry_run:
        print(f"Modified attributes: {modified_attributes}")
    else:
        with open(file_path, "w") as file:
            file.write(updated_content)


def rename_files_and_folders(path: Path, config: Config) -> None:
    EXCLUDES = [".godot", ".git"]
    if not config.process_addons:
        EXCLUDES.append("addons")

    if any(exclude in str(path) for exclude in EXCLUDES):
        return

    regex_path_attribute = re.compile(r'path="([^"]*)"')
    regex_gdscript_file_path = re.compile(r'"res://([^"]*)"')
    regex_gdscript_preload = re.compile(r'preload\("([^"]*)"')
    regex_autoload_file_path_string = re.compile(r'="\*?(res://[^"]*)"')

    for path_current in path.iterdir():
        if path_current.is_dir():
            rename_files_and_folders(path_current, config)

        if path_current.suffix in [".tscn", ".tres"]:
            update_file_content(path_current, config, [regex_path_attribute])
        elif path_current.suffix == ".gd":
            update_file_content(
                path_current, config, [regex_gdscript_file_path, regex_gdscript_preload]
            )
        elif path_current.name == "project.godot":
            update_file_content(path_current, config, [regex_autoload_file_path_string])

        path_new = path_current.with_name(to_snake_case(path_current.name))
        if path_current != path_new:
            if config.dry_run:
                print(f"Would rename: {path_current} -> {path_new}")
            else:
                subprocess.run(
                    ["git", "mv", str(path_current), str(path_new)],
                    check=True,
                    cwd=config.start_path,
                )


def run_tests() -> bool:
    # ANSI escape codes for colors
    GREEN = "\033[92m"
    RED = "\033[91m"
    RESET = "\033[0m"

    print(to_snake_case("LoopingAudioStreamPlayer2D.gd"))
    tests = [
        (
            "to_snake_case('Hello_World') should return 'hello_world'",
            lambda: to_snake_case("Hello_World") == "hello_world",
        ),
        (
            "to_snake_case('HelloWorld') should return 'hello_world'",
            lambda: to_snake_case("HelloWorld") == "hello_world",
        ),
        (
            "to_snake_case('LoopingAudioStreamPlayer2D.gd') should return 'looping_audio_stream_player_2d.gd'",
            lambda: to_snake_case("LoopingAudioStreamPlayer2D.gd")
            == "looping_audio_stream_player_2d.gd",
        ),
    ]

    passed_tests = 0
    total_tests = len(tests)
    for test_name, test_func in tests:
        result = test_func()
        status = f"{GREEN}PASSED{RESET}" if result else f"{RED}FAILED{RESET}"
        print(f"Test: {test_name} - {status}")
        if result:
            passed_tests += 1

    all_passed = passed_tests == total_tests
    summary = f"{GREEN}passed{RESET}" if all_passed else f"{RED}failed{RESET}"
    print(f"\nResult of running tests: {summary}.")
    print(f"Tests passed: {passed_tests}/{total_tests}")
    return all_passed


def main() -> None:
    config = parse_args()

    if config.run_tests:
        success = run_tests()
        exit(0 if success else 1)

    if config.dry_run:
        print("Running in dry-run mode. No changes will be made.")
    if not config.quiet:
        print(f"Starting renaming process in: {config.start_path}")

    try:
        rename_files_and_folders(config.start_path, config)
    except subprocess.CalledProcessError as e:
        print(f"Error executing git command: {e}")
        return

    if config.dry_run:
        print("Dry run completed. No changes were made.")
    elif not config.quiet:
        print("Renaming completed successfully.")


if __name__ == "__main__":
    main()
