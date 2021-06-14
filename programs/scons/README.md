# SCons usage guide

## Requirements:

- Install the requirements.txt file via pip: `pip3 install -r requirements.txt`. You can find `requirements.txt` in the parent directory.
- Install chroma for coloring HTML files.
- Copy the content of `to_copy/` into the directory you want to package.
- Inside the copied `SConstruct` file, update the `path_to_product_packager` variable to the absolute path to this directory.

## Usage:

In the directory you want to build, you can package a file by running Scons:

```sh
scons
```

A 'dist' directory will be created where packaged files will go. The program will convert any markdown files in a contents directory into formatted HTML files.

Additionally, Scons will bundle any present Godot projects into zip files in the same directory.

## Building an epub document

The --epub flag will let you export your project as an epub document in a local EpubDist directory.

```sh
scons --epub
```

## Build options

- **-c** the clean flag will remove all installed files in the build and dist directory. This is useful for proceeding to do a complete rebuild
- **-s** the silent flag will mute the majority of Scons logging, but colored success and error logs will still output.
- **--strict** the strict option will perform git version checks. the root directory and any git submodules will have their release flags compared. If any differ an error is raised.
