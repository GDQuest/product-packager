# TODO: after moving to our own MDX parser, we should test the system with real data from GDSchool.
import unittest
import strutils
import ../preprocessor/preprocessor
import ../settings
import ../preprocessor/cache

let appSettings = BuildSettings()
fileCache = prepareCache(appSettings)

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
