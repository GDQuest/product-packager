import unittest
import gdschool_preprocessor
import ../get_image_size

# NOTE: currently the paths are relative to where the tests are run from. You need to be in this directory to run the tests.
# TODO: make the tests use file paths and extract the dirpaths from the file paths, using functions from the program.
suite "gdschool_preprocessor":
  test "replaceMarkdownImages":
    let input =
      """![The character looking in different directions](images/020_075_runner_directions.png)"""
    let outputDirPath = "/"
    let inputDirPath = "test/"
    let expected =
      """<PublicImage src="/images/020_075_runner_directions.png" alt="The character looking in different directions" className="landscape-image" width="806" height="421"/>"""

    check replaceMarkdownImages(input, outputDirPath, inputDirPath) == expected

  test "replaceVideos":
    let input = """<VideoFile src="videos/010_overview_020_final_project.mp4" />"""
    let outputDirPath = "/courses/learn_2d_gamedev_godot_4/"
    let expected =
      """<VideoFile src="/courses/learn_2d_gamedev_godot_4/videos/010_overview_020_final_project.mp4" />"""

    check replaceVideos(input, outputDirPath) == expected

#  test "replaceVideos with different whitespace":
#    let input1 = """<VideoFile src="videos/test1.mp4"/>"""
#    let input2 = """<VideoFile  src="videos/test2.mp4" />"#""
#    let outputDirPath = "/test/path/"
#
#    let expected1 = """<VideoFile src=#"/test/path/videos/test1.mp4"/>"""
#    let expected2 = """<VideoFile src=#"/test/path/videos/test2.mp4"/>"""
#
#    check replaceVideos(input1, outputDirPath) == expected1
#
