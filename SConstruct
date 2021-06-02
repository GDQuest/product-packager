"""
https://scons.org/doc/production/PDF/scons-user.pdf
https://github.com/SCons/scons/wiki/SconsRecipes
"""
import scons_helper as helper
#  7.4.5 pyPackageDir

env = Environment()

AddOption('--Epub')

""" 
functionality:
compare submodule release tags and current to ensure they match, otherwise error out.

https://github.com/GDQuest/godot-pcg-secrets
this project uses the subodule and is a good test branch
"""

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

# Make environment variables available to subscripts
Export("env")

if env.GetOption("Epub"):
    SConscript("EpubSCsub")
else:
    SConscript("SCsub")
