"""A command-line tool for publishing lessons and chapters to the web.

The tool uses our course builds to generate a web page for each lesson, and
place each lesson in the right chapter.
"""
import re
import json
import dotenv
import os
import sys
from enum import Enum
from dataclasses import dataclass
from pathlib import Path
from typing import List, Sequence, Set, Generator, Dict, Tuple

import requests
from datargs import arg, parse

dotenv.load_dotenv()

YOUR_MAVENSEED_URL: str = os.environ.get("MAVENSEED_URL", "")
YOUR_EMAIL: str = os.environ.get("MAVENSEED_EMAIL", "")
YOUR_PASSWORD: str = os.environ.get("MAVENSEED_PASSWORD", "")

API_SLUG_LOGIN: str = "/api/login"
API_SLUG_COURSES: str = "/api/v1/courses"
API_SLUG_CHAPTERS: str = "/api/v1/chapters"
API_SLUG_COURSE_CHAPTERS: str = "/api/v1/course_chapters"
API_SLUG_LESSONS: str = "/api/v1/lessons"

ERROR_NO_VALID_LESSON_FILES: int = 1
ERROR_COURSE_NOT_FOUND: int = 2
ERROR_CACHE_FILE_EMPTY: int = 3

CACHE_FILE: Path = Path(".cache") / "courses.json"


class Status(Enum):
    """Valid status values for lessons in the Mavenseed API."""

    DRAFT: int = 0
    PUBLISHED: int = 1


class ResponseCodes(Enum):
    """Rest API response codes."""

    OK: int = 200
    CREATED: int = 201
    NO_CONTENT: int = 204
    BAD_REQUEST: int = 400
    UNAUTHORIZED: int = 401
    FORBIDDEN: int = 403
    NOT_FOUND: int = 404
    METHOD_NOT_ALLOWED: int = 405
    CONFLICT: int = 409
    UNPROCESSABLE_ENTITY: int = 422
    INTERNAL_SERVER_ERROR: int = 500
    NOT_IMPLEMENTED: int = 501


@dataclass
class Args:
    """Command-line arguments."""

    course: str = arg(
        positional=True,
        help="The name or URL slug of the course to upload the lessons to.",
    )
    lesson_files: Sequence[Path] = arg(
        positional=True,
        default=None,
        help="A sequence of paths to html files to upload to Mavenseed.",
    )
    overwrite: bool = arg(
        default=True,
        help="If set, overwrite existing lessons in the course. Otherwise, skip existing lessons.",
        aliases=["-o"],
    )
    mavenseed_url: str = arg(
        default=YOUR_MAVENSEED_URL,
        help="""the url of your mavenseed website.
        if you omit this option, the program tries to read it from the environment variable MAVENSEED_URL.
        """,
        aliases=["-u"],
    )
    email: str = arg(
        default=YOUR_EMAIL,
        help="""Your email to log into your Mavenseed's admin account.
        if you omit this option, the program tries to read it from the environment variable MAVENSEED_EMAIL.
        """,
        aliases=["-e"],
    )
    password: str = arg(
        default=YOUR_PASSWORD,
        help="""Your password to log into your Mavenseed's admin account.
        if you omit this option, the program tries to read it from the environment variable MAVENSEED_PASSWORD.
        """,
        aliases=["-p"],
    )
    list_courses: bool = arg(
        default=False,
        help="If true, list all courses on the Mavenseed website and exit.",
    )
    refresh_cache: bool = arg(
        default=False,
        aliases=["-r"],
        help="If True, resets the cache file before running the program."
        " This deletes thecache file and forces the program to re-query the Mavenseed API.",
    )
    delete: bool = arg(
        default=False,
        aliases=["-d"],
        help="If True, deletes the lessons instead of uploading them.",
    )
    verbose: bool = arg(
        default=False,
        aliases=["-v"],
        help="If True, prints more information about the process.",
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
            "excerpt": self.excerpt,
            "free": self.free,
            "questions_enabled": self.questions_enabled,
            "signin_required": self.signin_required,
            "view_count": self.view_count,
            "metadata": self.metadata,
            "banner_data": self.banner_data,
        }


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
            "content": self.content,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "ordinal": self.ordinal,
        }


@dataclass
class NewChapter:
    """Metadata for a new chapter to create on Mavenseed."""

    title: str
    course_id: int
    ordinal: int


@dataclass
class NewLesson:
    """Metadata for a new lesson to upload to Mavenseed."""

    title: str
    filepath: Path
    ordinal: int
    chapter_id: int = -1

    def get_file_content(self) -> str:
        """Return the content of the file to upload."""
        with open(self.filepath, "r") as f:
            return f.read()

    def get_title(self, content: str) -> str:
        """Return the title of the lesson from the content of the file to upload."""
        title = re.search(r"<title>(.*?)</title>", content)
        if title:
            return title.group(1)
        else:
            return self.slug.replace("-", " ").title()


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
            "exercise_votes_threshold": self.exercise_votes_threshold,
            "exercise_type": self.exercise_type,
            "free": self.free,
            "media_type": self.media_type,
            "signin_required": self.signin_required,
            "metadata": self.metadata,
            "embed_data": self.embed_data,
        }


def get_lesson_title(filepath: Path) -> str:
    lesson_title: str = ""
    with open(filepath) as f:
        while True:
            line = f.readline()
            if re.search(r"<title>", line):
                lesson_title = re.search(r"<title>(.*)</title>", line).group(1)
                break
            if re.search(r"<h1.*?>", line):
                lesson_title = re.search(r"<h1.*?>(.*)</h1>", line).group(1)
                break
            if not line:
                break
    assert lesson_title != "", (
        f"Unable to find the <title>or <h1> HTML tag in file {filepath}.\n"
        "This is required for the program to work."
    )
    return lesson_title.strip("'").replace("&#39;", "")


def cache_all_courses(url: str, auth_token: str) -> dict:
    """Downloads serializes all courses,chapters, and lessons through the Mavenseed API.
    Returns the data as a dictionary.
    Takes some time to execute, depending on the number of lessons and courses."""

    output = dict()

    def get_all_courses(api_url: str, auth_token: str) -> List[Course]:
        """Gets all course IDs from the Mavenseed API.

        Args:
            api_url: The URL of the Mavenseed API.
        Returns:
            A set of course IDs.
        """
        response = requests.get(
            api_url + API_SLUG_COURSES,
            headers={"Authorization": "Bearer " + auth_token},
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

    def get_all_lessons(
        api_url: str, auth_token: str, max_pages: int = -1
    ) -> Generator:
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

            if max_pages != -1 and page >= max_pages:
                break
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
        output[course.title] = {}
        output[course.title]["data"] = course.to_dict()
        output[course.title]["chapters"] = {}
        chapters: Dict[str, Chapter] = {
            chapter.title: chapter
            for chapter in get_all_chapters_in_course(url, auth_token, course.id)
        }
        for chapter_title in chapters:
            chapter: Chapter = chapters[chapter_title]
            lessons_in_chapter_as_dict = [
                lesson.to_dict()
                for lesson in lessons
                if lesson.lessonable_id == chapter.id
            ]
            chapter_as_dict = chapter.to_dict()
            chapter_as_dict["lessons"] = {
                lesson["slug"]: lesson for lesson in lessons_in_chapter_as_dict
            }
            output[course.title]["chapters"][chapter_title] = chapter_as_dict
    return output


def save_cache(cache: dict) -> None:
    if not CACHE_FILE.parent.exists():
        print("Creating .cache/ directory.")
        CACHE_FILE.parent.mkdir()
    print(f"Writing the data of {len(cache)} courses to {CACHE_FILE.as_posix()}.")
    json.dump(cache, open(CACHE_FILE, "w"), indent=2)


def does_chapter_exist_in_course(
    auth_token: str, api_url: str, chapter_id: int, course_id: int
) -> bool:
    """Makes an API request to the Mavenseed API to see if a chapter exists."""
    response = requests.get(
        f"{api_url}/{API_SLUG_CHAPTERS}/{chapter_id}",
        headers={"Authorization": "Bearer " + auth_token},
    )
    if response.status_code == ResponseCodes.OK.value:
        data: dict = response.json()
        return (
            data is not None
            and data["id"] == chapter_id
            and data["course_id"] == course_id
        )
    return False


def create_lesson(auth_token: str, api_url: str, new_lesson: NewLesson) -> dict:
    """Creates a new lesson via the Mavenseed API. Returns the lesson's data as a dictionary."""
    content: str = new_lesson.get_file_content()
    print(f"Creating lesson {new_lesson.title}.")
    response = requests.post(
        f"{api_url}/{API_SLUG_LESSONS}",
        headers={"Authorization": "Bearer " + auth_token},
        json={
            "lessonable_id": new_lesson.chapter_id,
            "lessonable_type": "Chapter",
            "title": new_lesson.title,
            "content": content,
            "ordinal": new_lesson.ordinal,
            "status": Status.PUBLISHED.value,
        },
    )
    if response.status_code != ResponseCodes.CREATED.value:
        raise Exception(
            f"Failed to create lesson {new_lesson.title}. Status code: {response.status_code}."
        )
    return response.json()


def update_lesson(auth_token: str, api_url: str, lesson: Lesson) -> dict:
    """Updates a lesson via the Mavenseed API. Returns the lesson's data as a dictionary."""
    print(f"Updating lesson {lesson.title}.")
    response = requests.patch(
        f"{api_url}/{API_SLUG_LESSONS}/{lesson.id}",
        headers={"Authorization": "Bearer " + auth_token},
        json={
            "title": lesson.title,
            "content": lesson.content,
            "status": Status.PUBLISHED.value,
        },
    )
    if response.status_code != ResponseCodes.OK.value:
        raise Exception(
            f"Failed to update lesson {lesson.title}. Status code: {response.status_code}."
        )
    return response.json()


def create_chapter(auth_token: str, api_url: str, new_chapter: NewChapter) -> dict:
    """Create a new chapter via the Mavenseed API. Returns the chapter's data as a dictionary."""
    print(f"Creating chapter {new_chapter.title}.")
    response = requests.post(
        f"{api_url}/{API_SLUG_CHAPTERS}",
        headers={"Authorization": "Bearer " + auth_token},
        json={
            "course_id": new_chapter.course_id,
            "title": new_chapter.title,
            "ordinal": new_chapter.ordinal,
        },
    )
    if response.status_code != 201:
        raise Exception(
            f"Failed to create chapter {new_chapter.title}. Status code: {response.status_code}."
        )
    return response.json()


def list_all_courses(auth_token: str, api_url: str) -> None:
    """Gets all courses from the Mavenseed API and prints their names."""
    print("Listing all courses.\n")
    response = requests.get(
        f"{api_url}/{API_SLUG_COURSES}",
        headers={"Authorization": "Bearer " + auth_token},
    )
    if response.status_code != 200:
        raise Exception(
            f"Failed to list all courses. Status code: {response.status_code}."
        )
    data = response.json()
    print(f"Found {len(data)} courses:\n")
    for course in data:
        print(f"- {course['title']} (id: {course['id']})")


def create_and_update_course(auth_token: str, args: Args) -> None:
    """Main function of the script.

    Validates arguments, then attempts to create new chapters and lessons or
    update existing lessons as needed.

    Caches the course data to a file and uses the cache to speed up execution.
    """

    def validate_files(args: Args) -> List[Path]:
        """Returns the list of valid html files passed in the command line arguments."""

        def validate_lesson_files(files: Sequence[Path]) -> List[Path]:
            """Validates the files to be uploaded to Mavenseed.

            Returns:
                A list of paths to files that should be uploaded.
            """

            def is_valid_file(filepath: Path) -> bool:
                """Returns true if the file is a valid lesson file.

                A valid lesson file is an html file that contains a valid
                <title> or <h1> tag.
                """
                if not filepath.exists() and filepath.suffix.lower() == ".html":
                    return False
                with filepath.open() as f:
                    content = f.read()
                    return (
                        re.search(r"<title>.*</title>", content) is not None
                        or re.search(r"<h1.*?>.*</h1>", content) is not None
                    )

            return [filepath for filepath in files if is_valid_file(filepath)]

        valid_files: List[Path] = validate_lesson_files(args.lesson_files)
        if len(valid_files) != len(args.lesson_files):
            invalid_files: Set[Path] = {
                filepath
                for filepath in args.lesson_files
                if filepath not in valid_files
            }
            for filepath in invalid_files:
                print(f"{filepath} is not a valid lesson file. It won't be uploaded.")
        if len(valid_files) == 0:
            print(
                "No valid lesson files found to upload in the provided list. Exiting."
            )
            sys.exit(ERROR_NO_VALID_LESSON_FILES)
        return valid_files

    def validate_and_update_cache(args: Args, auth_token: str) -> dict:
        cached_data: dict = {}

        if args.refresh_cache:
            print("Refreshing cache.")
            if CACHE_FILE.exists():
                CACHE_FILE.unlink()

        if CACHE_FILE.exists():
            with open(CACHE_FILE) as f:
                cached_data = json.load(f)
        else:
            print("Downloading and caching all data from Mavenseed.")
            cached_data = cache_all_courses(args.mavenseed_url, auth_token)
            save_cache(cached_data)

        if not cached_data:
            print("Cache file is empty. Exiting.")
            sys.exit(ERROR_CACHE_FILE_EMPTY)
        return cached_data

    def find_course_to_update(
        args: Args, auth_token: str, cached_data: dict
    ) -> Tuple[dict, Course]:
        """Finds the course matching the title passed as a command-line argument
        inside the cache.

        If no matching course is found, we offer the user to update the cache
        and return the new cache."""
        course_to_update: Course = None
        while not course_to_update:
            course_to_update = next(
                (
                    Course(**cached_data[course_title]["data"])
                    for course_title in cached_data.keys()
                    if course_title == args.course
                ),
                None,
            )
            if not course_to_update:
                print(
                    f"No cached course data found for the course named '{args.course}'. "
                    f"Do you want to update the course data? [y/N]"
                )
                if input().lower() != "y":
                    print("Course missing. Exiting.")
                    sys.exit(ERROR_COURSE_NOT_FOUND)
                else:
                    print("Updating course data.")
                    cached_data = cache_all_courses(args.mavenseed_url, auth_token)
                    save_cache(cached_data)
        return cached_data, course_to_update

    def get_lessons_in_course(course_chapters: dict) -> List[Lesson]:
        """Returns the list of all lessons in a course."""
        lessons_in_course: List[Lesson] = []
        for chapter_name in course_chapters:
            chapter_data: dict = course_chapters[chapter_name]
            for lesson_title in chapter_data["lessons"]:
                lesson_data: dict = chapter_data["lessons"][lesson_title]
                lessons_in_course.append(Lesson(**lesson_data, content=""))
        return lessons_in_course

    def map_lessons_to_chapters(valid_files: List[Path]) -> dict:
        """Turns file paths into a mapping of `chapter_name:
        List[Tuple[lesson_title, filepath]]`.

        Returns the new data structure."""
        lessons_map: dict = {}
        for filepath in valid_files:
            chapter_name: str = filepath.parent.name
            chapter_name = re.sub(r"[\-_]", " ", chapter_name)
            chapter_name = re.sub(r"\d+\.", "", chapter_name)
            chapter_name = chapter_name.capitalize()

            if not lessons_map.get(chapter_name):
                lessons_map[chapter_name] = []

            lesson_title: str = get_lesson_title(filepath)
            lessons_map[chapter_name].append((lesson_title, filepath))
        return lessons_map

    valid_files: List[Path] = validate_files(args)
    cached_data = validate_and_update_cache(args, auth_token)
    cached_data, course_to_update = find_course_to_update(args, auth_token, cached_data)

    # Preparing data to find which lessons to create or update.
    course_chapters: dict = cached_data[course_to_update.title]["chapters"]
    lessons_in_course: List[Lesson] = get_lessons_in_course(course_chapters)
    lessons_map: dict = map_lessons_to_chapters(valid_files)

    # Find all chapters and lessons to create or to update.
    chapter_loopindex: int = 1
    for chapter_name in lessons_map:
        chapters_filter: filter = filter(
            lambda k: k == chapter_name, course_chapters.keys()
        )
        matching_chapter_title: str = next(chapters_filter, "")
        matching_chapter: dict = (
            course_chapters[matching_chapter_title] if matching_chapter_title else {}
        )
        chapter_id: int = matching_chapter["id"] if matching_chapter else -1
        if not matching_chapter:
            new_chapter: NewChapter = NewChapter(
                title=chapter_name,
                course_id=course_to_update.id,
                ordinal=chapter_loopindex,
            )
            new_chapter_data: dict = create_chapter(
                auth_token, args.mavenseed_url, new_chapter
            )
            new_chapter_data["lessons"] = {}
            cached_data[course_to_update.title]["chapters"][
                chapter_name
            ] = new_chapter_data
            chapter_id = new_chapter_data["id"]
        chapter_loopindex += 1

        lesson_loopindex: int = 1
        for lesson_title, filepath in lessons_map[chapter_name]:
            lessons_filter: filter = filter(
                lambda l: l.title == lesson_title, lessons_in_course
            )
            lesson: Lesson = next(lessons_filter, None)
            if not lesson:
                if not does_chapter_exist_in_course(
                    auth_token, args.mavenseed_url, chapter_id, course_to_update.id
                ):
                    print(
                        f"Chapter {chapter_id} not found in course {course_to_update.title}.\n"
                        f"Skipping lesson {lesson_title}."
                    )
                    continue

                new_lesson: NewLesson = NewLesson(
                    title=lesson_title,
                    filepath=filepath,
                    ordinal=lesson_loopindex,
                    chapter_id=chapter_id,
                )
                new_lesson_data: dict = create_lesson(
                    auth_token, args.mavenseed_url, new_lesson
                )
                # We don't store the content to keep the cache smaller
                del new_lesson_data["content"]
                cached_data[course_to_update.title]["chapters"][chapter_name][
                    "lessons"
                ][new_lesson_data["title"]] = new_lesson_data
            else:
                content: str = ""
                with open(filepath) as f:
                    content = f.read()
                lesson.content = content
                assert (
                    content != ""
                ), f"Empty lesson content found for lesson {lesson.title}."
                update_lesson(auth_token, args.mavenseed_url, lesson)
            lesson_loopindex += 1

    # Save changes to cache file.
    print("Saving changes to cache file.")
    save_cache(cached_data)


def delete_lessons(auth_token: str, args: Args) -> None:
    """Deletes the lessons corresponding to the given course and lesson_files
    using the Mavenseed API."""

    def delete_lesson(auth_token: str, lesson_id: int) -> bool:
        """Deletes a lesson from the Mavenseed API.

        Returns True if the lesson was deleted, False otherwise."""
        print(f"Deleting lesson {lesson_id} from course {lesson_id}.")
        delete_url: str = f"{args.mavenseed_url}/{API_SLUG_LESSONS}/{lesson_id}"
        response: requests.Response = requests.delete(
            delete_url, headers={"Authorization": f"Bearer {auth_token}"}
        )
        if response.status_code != ResponseCodes.OK:
            print(
                f"Error deleting lesson {lesson_id}.\n"
                f"Response status code: {response.status_code}.\n"
                f"Response text: {response.text}"
            )
        return response.status_code == ResponseCodes.OK

    cached_data: dict = {}
    if CACHE_FILE.exists():
        with open(CACHE_FILE) as f:
            cached_data = json.load(f)
    if not cached_data:
        raise RuntimeError("Cache file empty.")

    lessons_to_delete: List[int] = [get_lesson_title(f) for f in args.lesson_files]
    course_to_update = cached_data[args.course]
    course_chapters: dict = course_to_update["chapters"]
    for chapter_name in course_chapters:
        chapter_data: dict = course_chapters[chapter_name]
        for lesson_title in chapter_data["lessons"]:
            if lesson_title not in lessons_to_delete:
                continue
            lesson_data: dict = chapter_data["lessons"][lesson_title]
            did_deletion_succeed: bool = delete_lesson(auth_token, lesson_data["id"])
            if did_deletion_succeed:
                del cached_data[course_to_update.title]["chapters"][chapter_name][
                    "lessons"
                ][lesson_title]

    print("Saving changes to cache file.")
    save_cache(cached_data)


def main():
    def get_auth_token(api_url: str, email: str, password: str) -> str:
        """Logs into the Mavenseed API using your email and password.

        Returns an auth token for future API calls."""
        response = requests.post(
            api_url + API_SLUG_LOGIN, data={"email": email, "password": password}
        )
        auth_token = response.json()["auth_token"]
        return auth_token

    args: Args = parse(Args)
    if not args.mavenseed_url:
        raise ValueError(
            """You must provide a Mavenseed URL via the --mavenseed-url command line
            option or set the MAVENSEED_URL environment variable."""
        )
    auth_token: str = get_auth_token(args.mavenseed_url, args.email, args.password)
    if args.list_courses:
        list_all_courses(auth_token, args.mavenseed_url)
        sys.exit(0)
    elif args.delete:
        delete_lessons(auth_token, args)
    else:
        create_and_update_course(auth_token, args)


if __name__ == "__main__":
    main()
