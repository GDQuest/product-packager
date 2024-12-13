import unittest
import tables
import strutils
import os
import preprocessor_rewrite
import ../types
import utils


let mockAppSettings = AppSettingsBuildGDSchool()
utils.cache = utils.prepareCache(mockAppSettings)

suite "MDX Preprocessor":
  setup:
    createDir("temp_input")
    createDir("temp_output")

  teardown:
    removeDir("temp_input")
    removeDir("temp_output")

  test "Process Godot icon replacement":
    let input = "Here's a Node2D class reference"
    let result = processContent("`Node2D`", "", "", mockAppSettings)
    check result.contains("<IconGodot name=\"Node2D\"/>")
    check result.contains("`Node2D`")

  test "Process video file component":
    let input = "<VideoFile src=\"path/to/video.mp4\"/>"
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result.contains("temp_output/path/to/video.mp4")

  test "Process Include component with anchor":
    # Create a test file with anchors
    let testCode = """
#ANCHOR: test-section
func test():
    print("Hello")
#END: test-section
"""
    writeFile("temp_input/test.gd", testCode)

    let input = """<Include file="test.gd" anchor="test-section"/>"""
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result.contains("func test():")
    check not result.contains("ANCHOR")
    check not result.contains("END")

  test "Process Include component with dedent":
    let testCode = """
#ANCHOR: dedent-test
    func test():
        print("Hello")
#END: dedent-test
    """
    writeFile("temp_input/dedent.gd", testCode)

    let input = """<Include file="dedent.gd" anchor="dedent-test" dedent="4"/>"""
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result.contains("func test():")
    check not result.contains("    func test():")

  test "Process Include component with prefix":
    let testCode = """
#ANCHOR: prefix-test
func test():
    print("Hello")
#END: prefix-test
    """
    writeFile("temp_input/prefix.gd", testCode)

    let input = """<Include file="prefix.gd" anchor="prefix-test" prefix="+ "/>"""
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result.contains("+ func test():")

  test "Process Include component with replace":
    let testCode = """
#ANCHOR: replace-test
func old_name():
    print("Hello")
#END: replace-test
    """
    writeFile("temp_input/replace.gd", testCode)

    let input = """<Include file="replace.gd" anchor="replace-test" replace='{"source": "old_name", "replacement": "new_name"}'/>"""
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result.contains("new_name")
    check not result.contains("old_name")

  test "Process markdown image":
    # Create a test image file
    writeFile("temp_input/test.png", "dummy image data")

    let input = "![Alt text](test.png)"
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result.contains("<PublicImage")
    check result.contains("temp_output/test.png")
    check result.contains("Alt text")

  test "Handle multiple patterns in single content":
    let input = """
# Test content
`Node2D` is a class.
![Image](test.png)
<VideoFile src="video.mp4"/>
"""
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result.contains("<IconGodot")
    check result.contains("<PublicImage")
    check result.contains("<VideoFile")

  test "Handle non-existing patterns":
    let input = "Regular text without any special patterns"
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result == input

  test "Handle empty input":
    let result = processContent(
      "",
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result == ""

  test "Handle invalid include file":
    let input = """<Include file="non_existing.gd" anchor="test"/>"""
    let result = processContent(
      input,
      "temp_input",
      "temp_output",
      mockAppSettings
    )
    check result == input
    check preprocessorErrorMessages.len > 0
