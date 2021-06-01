"""
https://scons.org/doc/production/PDF/scons-user.pdf
https://github.com/SCons/scons/wiki/SconsRecipes
"""
import scons_helper as helper
#  7.4.5 pyPackageDir

BUILD_DIR = "build/"
DIST_DIR = "dist/"

env = Environment()

"""
build targets:
update - update any git submodules containing project code
epub - compile all into one location and process as one doc
this will require custom css

AddOption(
    '--Epub',
    dest='epub',
)
    
functionality:
compare submodule release tags and current to ensure they match, otherwise error out.

https://github.com/GDQuest/godot-pcg-secrets
this project uses the subodule and is a good test branch
"""

if env.GetOption("clean"):
    Execute(Delete("build"))
    Execute(Delete("dist"))

HTMLBuilder = Builder(action=helper.process_markdown_file_in_place,
        suffix='.html',
        src_suffix='.md',
        single_source=1,
        )

env['BUILDERS']["HTMLBuilder"] = HTMLBuilder

GDBuilder = Builder(action=helper.bundle_godot_project,
        suffix='.zip',
        )

env['BUILDERS']["GDBuilder"] = GDBuilder

if not COMMAND_LINE_TARGETS:
    helper.err_log("missing targets")
    Exit(1)

src = COMMAND_LINE_TARGETS[0]


VariantDir(BUILD_DIR, src, duplicate=False)

if not helper.validate_source_dir(src):
    helper.err_log("SRC dir invalid")
    Exit(1)

src_path = helper.pathlib.Path(src) / "content"
src_contents = helper.content_introspection(src)

images = []
for folder in src_contents:
    images.extend(
        helper.glob_extensions(folder, ["*.png", "*.jpg", "*.svg"])
    )
ilist = []
for image_path in images:
    ilist.append(Install(BUILD_DIR + image_path.relative_to(src_path).parent.as_posix(), image_path.as_posix()))

videos = []
for folder in src_contents:
    videos.extend(
        helper.glob_extensions(folder, ["*.mp4", "*.jpg"])
    )
vlist = []
for video_path in videos:
    vlist.append(Install(BUILD_DIR + video_path.relative_to(src_path).parent.as_posix(), video_path.as_posix()))

markdown_files = []
for folder in src_contents:
    markdown_files.extend(helper.glob_extensions(folder, ["*.md"]))
for markdown_path in markdown_files:
    targ = BUILD_DIR + markdown_path.relative_to(src_path).as_posix()
    Install(BUILD_DIR + markdown_path.relative_to(src_path).parent.as_posix(), markdown_path.as_posix())
    build_html_file = env.HTMLBuilder(targ)
    env.AddPostAction(build_html_file, Delete(targ))
    for image in ilist:
        Depends(build_html_file, image)
    for video in vlist:
        Depends(build_html_file, video)

for folder in helper.get_godot_folders(src):
    gd_name = helper.get_godot_filename(folder)
    env.GDBuilder(BUILD_DIR + gd_name + ".zip", folder + "/project.godot")