"""
https://scons.org/doc/production/PDF/scons-user.pdf
https://github.com/SCons/scons/wiki/SconsRecipes
"""
import scons_helper as helper
#  7.4.5 pyPackageDir

env = Environment()

AddOption('--Epub')

GDBuilder = Builder(action=helper.bundle_godot_project,
        suffix='.zip',
        )

env['BUILDERS']["GDBuilder"] = GDBuilder

if env.GetOption("clean"):
    Execute(Delete("build"))
    Execute(Delete("dist"))

if not COMMAND_LINE_TARGETS:
    helper.err_log("missing targets")
    Exit(1)

env["src"] = COMMAND_LINE_TARGETS[0]

if not helper.validate_source_dir(env["src"]):
    helper.err_log("SRC dir invalid")
    Exit(1)

env["content_folder_path"] = helper.pathlib.Path(env["src"]) / "content"
env["contents_folders"] = helper.content_introspection(env["src"])

# Gather images
env["images"] = []
for folder in env["contents_folders"]:
    env["images"].extend(
        helper.glob_extensions(folder, ["*.png", "*.jpg", "*.svg"])
    )
# Gather videos
env["videos"] = []
for folder in env["contents_folders"]:
    env["videos"].extend(
        helper.glob_extensions(folder, ["*.mp4", "*.jpg"])
    )
# Gather markdown files
env["markdown_files"] = []
for folder in env["contents_folders"]:
    env["markdown_files"].extend(
        helper.glob_extensions(folder, ["*.md"])
    )

# Make environment variables available to subscripts
Export("env")

if env.GetOption("Epub"):
    SConscript("EpubSCsub")
else:
    SConscript("SCsub")

# package godot projects (after Sconscript so build dir is defined
for folder in helper.get_godot_folders(env["src"]):
    gd_name = helper.get_godot_filename(folder)
    env.GDBuilder(env["DIST_DIR"] + gd_name + ".zip", folder + "/project.godot")