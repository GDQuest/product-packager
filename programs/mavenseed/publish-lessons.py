"""A command-line tool for publishing lessons and chapters to the web.

The tool uses our course builds to generate a web page for each lesson, and
place each lesson in the right chapter.
"""
import logging
import re
import json
import os
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import List, Sequence, Set, Dict, Generator

import requests
from datargs import arg, parse

YOUR_MAVENSEED_URL: str = os.environ.get("MAVENSEED_URL", "")

API_SLUG_LOGIN: str = "/api/login"
API_SLUG_COURSES: str = "/api/v1/courses"
API_SLUG_CHAPTERS: str = "/api/v1/chapters"
API_SLUG_COURSE_CHAPTERS: str = "/api/v1/course_chapters"
API_SLUG_LESSONS: str = "/api/v1/lessons"

ERROR_NO_VALID_LESSON_FILES: int = 1
ERROR_COURSE_NOT_FOUND: int = 2
ERROR_CACHE_FILE_EMPTY: int = 3

CACHE_FILE: Path = Path(".cache") / "courses.json"


@dataclass
class Args:
    """Command-line arguments."""

    course: str = arg(
        positional=True,
        help="The name or URL slug of the course to upload the lessons to.",
    )
    lesson_files: Sequence[Path] = arg(
        positional=True,
        help="A sequence of paths to html files to upload to Mavenseed.",
    )
    overwrite: bool = arg(
        default=True,
        help="If set, overwrite existing lessons in the course. Otherwise, skip existing lessons.",
        aliases=["-o"],
    )
    mavenseed_url: str = arg(
        default=YOUR_MAVENSEED_URL,
        help="""The URL of your Mavenseed website.
        If you omit this option, the program tries to read it from the environment variable MAVENSEED_URL.
        """,
        aliases=["-u"],
    )
    list_courses: bool = arg(
        default=False, help="List all courses on the Mavenseed website and their ID."
    )


@dataclass
class Course:
    """Metadata for a course returned by the Mavenseed API."""

    id: int
    title: str
    slug: str
    status: str
    created_at: str
    updated_at: str
    scheduled_at: str
    published_at: str
    excerpt: str
    free: bool
    questions_enabled: bool
    signin_required: bool
    view_count: int
    metadata: dict
    banner_data: object

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "slug": self.slug,
            "status": self.status,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "scheduled_at": self.scheduled_at,
            "published_at": self.published_at,
        }


@dataclass
@dataclass
class Chapter:
    """Metadata for a chapter returned by the Mavenseed API."""

    id: int
    course_id: int
    title: str
    content: str
    created_at: str
    updated_at: str
    ordinal: int

    def to_dict(self):
        return {
            "id": self.id,
            "course_id": self.course_id,
            "title": self.title,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "ordinal": self.ordinal,
        }


@dataclass
class Lesson:
    """Metadata for a lesson returned by the Mavenseed API."""

    id: int
    lessonable_type: str
    lessonable_id: int
    title: str
    slug: str
    content: str
    status: str
    created_at: str
    updated_at: str
    ordinal: int
    exercise_votes_threshold: int
    exercise_type: int
    free: bool
    media_type: str
    signin_required: bool
    metadata: dict
    embed_data: object

    def to_dict(self):
        """Convert the lesson to a dictionary."""
        return {
            "id": self.id,
            "lessonable_type": self.lessonable_type,
            "lessonable_id": self.lessonable_id,
            "title": self.title,
            "slug": self.slug,
            "status": self.status,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "ordinal": self.ordinal,
        }


def validate_lesson_files(files: Sequence[Path]) -> List[Path]:
    """Validates the files to be uploaded to Mavenseed.

    Returns:
        A list of paths to files that should be uploaded.
    """

    def is_valid_file(filepath: Path) -> bool:
        """Returns true if the file is a valid lesson file.

        A valid lesson file is an html file that contains a valid lesson header.
        """
        is_valid: bool = filepath.exists() and filepath.suffix.lower() == ".html"
        with filepath.open() as f:
            return is_valid and bool(re.search(r"<h1>.*</h1>", f.read()))

    return [filepath for filepath in files if is_valid_file(filepath)]


def upload_lesson(
    token: str, course_id: str, lesson_file: Path, overwrite: bool = True
) -> None:
    """Uploads a lesson to Mavenseed using the requests module.

    Args:
        token: your Mavenseed API token.
        course_id: The ID of the course to upload the lesson to.
        lesson_file: The path to the lesson file to upload.
        overwrite: If set, overwrite existing lessons in the course. Otherwise, skip existing lessons.
    """
    pass


def get_auth_token(api_url: str, email: str, password: str) -> str:
    """Logs into the Mavenseed API using your email, password,and API token.

    Args:
        api_url: The URL of the Mavenseed API.
        auth_token: A string containing the API token.
    Returns:
        The authorization token.
    """
    response = requests.post(
        api_url + API_SLUG_LOGIN, data={"email": email, "password": password}
    )
    auth_token = response.json()["auth_token"]
    return auth_token


def get_api_token(token: str = None) -> str:
    """Gets the Mavenseed API token from the environment.

    Args:
        token: A string containing the API token. If this is omitted, the
            program tries to read it from the environment variable MAVENSEED_TOKEN.
    Returns:
        A string containing the API token.
    """
    if token is None:
        token = os.environ.get("MAVENSEED_TOKEN")
    if token is None:
        raise ValueError(
            """You must either provide a token via the --token command line
            option or set the MAVENSEED_TOKEN environment variable."""
        )
    return token


def get_all_courses(api_url: str, auth_token: str) -> List[Course]:
    """Gets all course IDs from the Mavenseed API.

    Args:
        api_url: The URL of the Mavenseed API.
    Returns:
        A set of course IDs.
    """
    response = requests.get(
        api_url + API_SLUG_COURSES, headers={"Authorization": "Bearer " + auth_token}
    )

    courses: List[Course] = [Course(**course) for course in response.json()]
    return courses


def get_all_chapters_in_course(
    api_url: str, auth_token: str, course_id: int
) -> List[Chapter]:
    """Gets all chapters from the Mavenseed API.

    Args:
        api_url: The URL of the Mavenseed API.
        auth_token: A string containing the API token.
        course_id: The ID of the course to get the chapters from.
    Returns:
        A set of chapters.
    """
    print(f"Getting chapters for course {course_id}.", end="\r")
    response = requests.get(
        f"{api_url}/{API_SLUG_COURSE_CHAPTERS}/{course_id}",
        headers={"Authorization": "Bearer " + auth_token},
    )
    chapters: List[Chapter] = [Chapter(**data) for data in response.json()]
    return chapters




def cache_all_courses(url: str, auth_token: str) -> None:
    """Downloads serializes all courses,chapters, and lessons through the Mavenseed API.
    Returns the data as a dictionary.
    Takes some time to execute, depending on the number of lessons and courses."""

    output = dict()

    def get_all_lessons(api_url: str, auth_token: str) -> Generator:
        """Generator. Gets all lessons from the Mavenseed API.

        Args:
            api_url: The URL of the Mavenseed API.
            auth_token: A string containing the API token.
            course_id: The ID of the course to get the lessons from.
        Returns:
            A set of lessons.
        """
        page: int = 0
        while True:
            print(f"Getting lessons {page * 20} to {(page + 1) * 20}", end="\r")
            response = requests.get(
                f"{api_url}/{API_SLUG_LESSONS}",
                headers={"Authorization": "Bearer " + auth_token},
                params={"page": page},
            )
            lessons: List[Lesson] = [Lesson(**data) for data in response.json()]
            page += 1
            if not lessons:
                break
            yield lessons

    print("Downloading all lessons, chapters, and course data. This may take a while.")
    lessons_lists: List[List[Lesson]] = list(get_all_lessons(url, auth_token))
    lessons: List[Lesson] = [
        lesson for lesson_list in lessons_lists for lesson in lesson_list
    ]

    courses: List[Course] = get_all_courses(url, auth_token)
    for course in courses:
        output[course.title] = []
        chapters: List[Chapter] = get_all_chapters_in_course(url, auth_token, course.id)
        for chapter in chapters:
            lessons_in_chapter_as_dict = [
                lesson.to_dict()
                for lesson in lessons
                if lesson.lessonable_id == chapter.id
            ]
            # convert each Chapter object to a dictionary
            chapter_as_dict = chapter.to_dict()
            chapter_as_dict["lessons"] = lessons_in_chapter_as_dict
            output[course.title].append(chapter_as_dict)

    if not CACHE_FILE.parent.exists():
        print("Creating .cache/ directory.")
        CACHE_FILE.parent.mkdir()
    print(f"Writing the data of {len(output)} courses to {CACHE_FILE.as_posix()}.")
    json.dump(output, open(CACHE_FILE, "w"), indent=2)



def main_final():
    args: Args = parse(Args)

    if not args.mavenseed_url:
        raise ValueError(
            """You must provide a Mavenseed URL via the --mavenseed-url command line
            option or set the MAVENSEED_URL environment variable."""
        )

    valid_files: List[Path] = validate_lesson_files(args.lesson_files)
    if len(valid_files) != len(args.lesson_files):
        invalid_files: Set[Path] = {
            filepath for filepath in args.lesson_files if filepath not in valid_files
        }
        for filepath in invalid_files:
            print(
                f"{filepath} is not a valid lesson file. It won't be uploaded."
            )
    if len(valid_files) == 0:
        print("No valid lesson files found to upload in the provided list. Exiting.")
        sys.exit(ERROR_NO_VALID_LESSON_FILES)

    auth_token: str = get_auth_token(args.mavenseed_url, args.email, args.password)

    if not CACHE_FILE.exists():
        print("Cache file not found. Downloading and caching all data from Mavenseed.")
        cache_all_courses(args.mavenseed_url, auth_token)

    cached_data: dict = {}
    with open(CACHE_FILE) as f:
        cached_data = json.load(f)
    if not cached_data:
        print("Cache file is empty. Exiting.")
        sys.exit(ERROR_CACHE_FILE_EMPTY)

    # Get all courses and ensure we don't try to upload to a nonexistent course.
    courses: List[Course] = get_all_courses(args.mavenseed_url, auth_token)
    if args.list_courses:
        for course in courses:
            print(f"{course.id} - {course.title}")
        sys.exit(0)

    course_to_update: Course
    try:
        course_to_update = next(
            course
            for course in courses
            if args.course_title in (course.title, course.slug)
        )
    except StopIteration:
        print("No course found with the given title or url slug: {desired_course}. Exiting.")
        sys.exit(ERROR_COURSE_NOT_FOUND)


    course_chapters: dict = cached_data[course_to_update.title]
    #TODO: convert each file path to a chapter and lesson slug
    #TODO: determine if the chapter already exists in the course. If not, create it.
    #TODO: determine if the lesson already exists in the chapter. If not, create it.
    # If it does, update the lesson.
    #TODO: also ensure that the lesson isn't a duplicate name - check the chapter and lesson ids match - and that the chapter is part of the course.
    #TODO: update the cache file with newly created lessons and chapters.
    for filepath in args.files:
        chapter_slug: str = filepath.parent.name.lower().replace(" ", "-")
        lesson_slug: str = filepath.stem.lower().replace(" ", "-")
        
        logging.info(f"Uploading {filepath} to Mavenseed")
        upload_lesson(auth_token, filepath, args.course, args.token, args.overwrite)


if __name__ == "__main__":
    main()
