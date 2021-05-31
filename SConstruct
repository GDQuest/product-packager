"""
https://scons.org/doc/production/PDF/scons-user.pdf
https://github.com/SCons/scons/wiki/SconsRecipes
"""
import scons_helper as helper

# TODO: 7.4.5 pyPackageDir

BUILD_DIR = "build"
DIST_DIR = "dist"

env = Environment()

# AddOption(
#     '--Epub',
#     dest='epub',
    # nargs=1,
    # type='boolean',
    # action='store',
    # metavar='DIR',
    # help='installation prefix',
# )

# if env.GetOption("clean"):
#     Execute(Delete("build"))
#     Execute(Delete("dist"))

HTMLBuilder = Builder(action=helper.process_markdown_file_in_place,
        suffix='.html',
        src_suffix='.md',
        single_source=1,
        )

env['BUILDERS']["HTMLBuilder"] = HTMLBuilder

if not COMMAND_LINE_TARGETS:
    print("missing targets")
    Exit(1)

src = COMMAND_LINE_TARGETS[0]

VariantDir(BUILD_DIR, src, duplicate=False)

if not helper.validate_source_dir(src):
    print("SRC dir invalid")
    Exit(1)

Execute(Mkdir(BUILD_DIR + '/images'))
Execute(Mkdir(BUILD_DIR + '/videos'))

class_dir = Dir(BUILD_DIR)

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

markdown_files = []
for folder in src_contents:
    markdown_files.extend(helper.glob_extensions(folder, ["*.md"]))
for markdown_path in markdown_files:
    targ = BUILD_DIR + '/' + markdown_path.name
    Execute(Copy(targ, markdown_path.as_posix()))
    htarg = helper.extension_to_html(targ)
    build_html_file = env.HTMLBuilder(targ)
    env.AddPostAction(build_html_file, Delete(targ))
# print(env.Dump())