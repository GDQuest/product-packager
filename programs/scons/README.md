# SCons usage guide

## Requirements:
- Install the requirements.txt file via pip.
- Install chroma for coloring HTML files.

## Usage:

In the program's directory, you can package a file by running Scons and passing a path to the directory to package as a parameter:

```sh
scons ../../../godot-pcg-secrets/ 
```

If a path to a target directory isn't passed in, the program will raise an error.

A 'dist' directory will be created where packaged files will go. The program will convert any markdown files in a contents directory into formatted HTML files.

Additionally, Scons will bundle any present Godot projects into zip files in the same directory.

## Building an epub document

The --epub flag will let you export your project as an epub document in a local EpubDist directory.

```sh
scons --epub ../../../godot-pcg-secrets/ 
```

## Build options

- **-c** the clean flag will remove all installed files in the build and dist directory. This is useful for proceeding to do a complete rebuild
- **-s** the silent flag will mute the majority of Scons logging, but colored success and error logs will still output.
- **--strict** the strict option will perform git version checks. the root directory and any git submodules will have their release flags compared. If any differ an error is raised.