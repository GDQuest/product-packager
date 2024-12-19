# TODO: move to tests/ director
# TODO: instead of doing setup and teardown, prepare a sample project with all the files needed for a true integration test:
# - a Godot project with a script file
# - a content folder with markdown files
# - images and videos
# - a folder with the expected output
# - a configuration file
import unittest
import strutils
import ../gdschool_preprocessor
import ../../settings
import ../utils

let appSettings = AppSettingsBuildGDSchool()
utils.cache = utils.prepareCache(appSettings)

suite "MDX Preprocessor":
  test "Process Godot icon replacement":
    let result = processContent("`Node2D`", "", "", appSettings)
    check result.contains("<IconGodot name=\"Node2D\"/>")
    check result.contains("`Node2D`")

  test "Process video file component":
    let input = "<VideoFile src=\"path/to/video.mp4\"/>"
    let result = processContent(input, ".", "temp_output", appSettings)
    check result.contains("temp_output/path/to/video.mp4")

  test "Process markdown image":
    let input = "![Alt text](images/020_075_runner_directions.png)"
    let result = processContent(input, ".", "/public", appSettings)
    check result.contains("<PublicImage")
    check result.contains("/public/images/020_075_runner_directions.png")
    check result.contains("Alt text")

  test "Handle multiple patterns in single content":
    let input =
      """
# Test content
`Node2D` is a class.
![Image](images/020_075_runner_directions.png)
<VideoFile src="video.mp4"/>
"""
    let result = processContent(input, ".", "temp_output", appSettings)
    check result.contains("<IconGodot")
    check result.contains("<PublicImage")
    check result.contains("<VideoFile")

  test "Handle non-existing patterns":
    let input = "Regular text without any special patterns"
    let result = processContent(input, ".", "temp_output", appSettings)
    check result == input

  test "Handle empty input":
    let result = processContent("", ".", "temp_output", appSettings)
    check result == ""
