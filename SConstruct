"""
https://github.com/SCons/scons/wiki/SconsRecipes
"""
# for code completion
import SCons.Script
from SCons.Environment import Environment
from SCons.Variables import Variables
from SCons.Variables import PathVariable
import scons_helper as helper

BUILD_DIR = "build"
DIST_DIR = "dist"

if "clean" in COMMAND_LINE_TARGETS:
    remove_directory("build")
    remove_directory("dist")

env = Environment()

HTMLBuilder = Builder(action=helper.process_markdown_file_in_place,
        suffix='.html',
        src_suffix='.md',
        # single_source=1,
        )
# helper.remove_figcaption()
#https://scons-cookbook.readthedocs.io/en/latest/#defining-your-own-builder-object
# TODO: use this to call the conversion script
env['BUILDERS']["HTMLBuilder"] = HTMLBuilder

if not COMMAND_LINE_TARGETS:
    print("missing targets")
    Exit(1)
src = COMMAND_LINE_TARGETS[0]
if not helper.validate_source_dir(src):
    print("SRC dir invalid")
    Exit(1)
Execute(Mkdir(BUILD_DIR + '/images'))
Execute(Mkdir(BUILD_DIR + '/videos'))

src_contents = helper.content_introspection(src)


#copy the image files into an images folder
images = []
for folder in src_contents:
    images.extend(
        helper.glob_extensions(folder, ["*.png", "*.jpg"])
    )
for image_path in images:
    Execute(Copy(BUILD_DIR + '/images/' + image_path.name, image_path.as_posix()))

#copy the video files into a videos folder
videos = []
for folder in src_contents:
    videos.extend(
        helper.glob_extensions(folder, ["*.mp4", "*.jpg"])
    )
for video_path in videos:
    Execute(Copy(BUILD_DIR + '/videos/' + video_path.name, video_path.as_posix()))

# chroma needs to be installed


# Todo:, change env to not copy md files as they are replaced, the html files should be the dependency
# copy markdown files into the root
markdown_files = []
for folder in src_contents:
    markdown_files.extend(helper.glob_extensions(folder, ["*.md"]))
for markdown_path in markdown_files:
    targ = BUILD_DIR + '/' + markdown_path.name
    Execute(Copy(targ, markdown_path.as_posix()))
    # helper.process_markdown_file_in_place(BUILD_DIR + '/' + markdown_path.name)
    htarg = helper.extension_to_html(targ)
    env.HTMLBuilder(htarg, targ, env)
    print(env.HTMLBuilder)

# env.Zip('archive', [BUILD_DIR])