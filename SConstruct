"""
useful docs
https://github.com/godotengine/godot/blob/master/SConstruct
https://github.com/SCons/scons/wiki/SconsProcessOverview
https://www.scons.org/doc/1.1.0/HTML/scons-user/x2361.html

by default this uses md5 checksums to check if source files have changed.
"""
# for code completion
import SCons.Script
from SCons.Environment import Environment
from SCons.Variables import Variables
from SCons.Variables import PathVariable
import scons_helper as helper

env = Environment()

if not 'SRC' in ARGUMENTS:
    print("missing SRC")
    Exit(1)
src = ARGUMENTS.get("SRC", "/")
if not helper.validate_source_dir(src):
    print("SRC dir invalid")
    Exit(1)

Execute(Mkdir('results/images'))
Execute(Mkdir('results/videos'))

src_contents = helper.content_introspection(src)

images = []
for folder in src_contents:
    images.extend(
        helper.capture_folder(folder, "images", ["*.png", "*.jpg"])
    )
for image_path in images:
    Execute(Copy('results/images/' + image_path.name, image_path.as_posix()))

videos = []
for folder in src_contents:
    videos.extend(
        helper.capture_folder(folder, "videos", ["*.mp4", "*.jpg"])
    )
for video_path in videos:
    Execute(Copy('results/videos/' + video_path.name, video_path.as_posix()))

env.Zip('archive', ['results'])