# TODO: move to tests/ director
# TODO: instead of doing setup and teardown, prepare a sample project with all the files needed for a true integration test:
# - a Godot project with a script file
# - a content folder with markdown files
# - images and videos
# - a folder with the expected output
# - a configuration file
import unittest
import strutils
import ../preprocessor_rewrite
import ../../types
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
    let result = processContent(
      input,
      ".",
      "temp_output",
      appSettings
    )
    check result.contains("temp_output/path/to/video.mp4")

  test "Process markdown image":
    let input = "![Alt text](images/020_075_runner_directions.png)"
    let result = processContent(
      input,
      ".",
      "/public",
      appSettings
    )
    check result.contains("<PublicImage")
    check result.contains("/public/images/020_075_runner_directions.png")
    check result.contains("Alt text")

  test "Handle multiple patterns in single content":
    let input = """
# Test content
`Node2D` is a class.
![Image](images/020_075_runner_directions.png)
<VideoFile src="video.mp4"/>
"""
    let result = processContent(
      input,
      ".",
      "temp_output",
      appSettings
    )
    check result.contains("<IconGodot")
    check result.contains("<PublicImage")
    check result.contains("<VideoFile")

  test "Handle non-existing patterns":
    let input = "Regular text without any special patterns"
    let result = processContent(
      input,
      ".",
      "temp_output",
      appSettings
    )
    check result == input

  test "Handle empty input":
    let result = processContent(
      "",
      ".",
      "temp_output",
      appSettings
    )
    check result == ""

#   test "Handle invalid include file":
#     let input = """<Include file="non_existing.gd" anchor="test"/>"""
#     let result = processContent(
#       input,
#       ".",
#       "temp_output",
#       appSettings
#     )
#     check result == input
#     check preprocessorErrorMessages.len > 0

#   test "Process Include component with anchor":
#     # Create a test file with anchors

#     let input = """<Include file="test.gd" anchor="test-section"/>"""
#     let result = processContent(
#       input,
#       ".",
#       "temp_output",
#       appSettings
#     )
#     check result.contains("func test():")
#     check not result.contains("ANCHOR")
#     check not result.contains("END")

#   test "Process Include component with dedent":
#     let testCode = """
# #ANCHOR: dedent-test
#     func test():
#         print("Hello")
# #END: dedent-test
#     """
#     writeFile("./dedent.gd", testCode)

#     let input = """<Include file="dedent.gd" anchor="dedent-test" dedent="4"/>"""
#     let result = processContent(
#       input,
#       ".",
#       "temp_output",
#       appSettings
#     )
#     check result.contains("func test():")
#     check not result.contains("    func test():")

#   test "Process Include component with prefix":
#     let testCode = """
# #ANCHOR: prefix-test
# func test():
#     print("Hello")
# #END: prefix-test
#     """
#     writeFile("./prefix.gd", testCode)

#     let input = """<Include file="prefix.gd" anchor="prefix-test" prefix="+ "/>"""
#     let result = processContent(
#       input,
#       ".",
#       "temp_output",
#       appSettings
#     )
#     check result.contains("+ func test():")

#   test "Process Include component with replace":
#     let testCode = """
# #ANCHOR: replace-test
# func old_name():
#     print("Hello")
# #END: replace-test
#     """
#     writeFile("./replace.gd", testCode)

#     let input = """<Include file="replace.gd" anchor="replace-test" replace='{"source": "old_name", "replacement": "new_name"}'/>"""
#     let result = processContent(
#       input,
#       ".",
#       "temp_output",
#       appSettings
#     )
#     check result.contains("new_name")
#     check not result.contains("old_name")
