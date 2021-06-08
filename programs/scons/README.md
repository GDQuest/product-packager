# SCons usage guide

## Requirements:
- Install the requirements.txt file via pip.
- Install chroma for coloring HTML files.
- Copy the scons/SConstruct file into the directory you want to package
- update `path_to_product_packager` in the SConstruct file to the absolute path to the product-packager/programs directory.

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