import std/[unittest, tables, os]
import get_image_size

let DIR_THIS = currentSourcePath.parentDir()
let testImages = {
  "010_practice_example.png": ImageDimensions(width: 987, height: 636),
  "040-laptop-code.jpg": ImageDimensions(width: 810, height: 540),
  "learn-gamedev-2d-dialogue-system.webp": ImageDimensions(width: 1280, height: 720),
}.toTable()

suite "Image Dimension Tests":
  test "Get image dimensions":
    for imagePath, expectedDimensions in testImages.pairs:
      let path = DIR_THIS / "test/images" / imagePath
      echo "Checking image dimensions for: ", path
      let dimensions = getImageDimensions(path)
      check dimensions == expectedDimensions

  test "Handle non-existent file":
    expect IOError:
      discard getImageDimensions("non_existent_file.png")

  test "Handle unsupported format":
    expect IOError:
      discard getImageDimensions("images/test.gif")