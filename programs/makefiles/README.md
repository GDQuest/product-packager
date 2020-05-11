# Automate product builds with make

To build course releases (render videos, export documents...), we use [GNU make](https://www.gnu.org/software/make/). Make is a program that builds files based on a set of rules and dependencies.

For example, we use it to automatically detect and compress new or modified pictures:

```makefile
build/images/%: images/%
	cp $< $@
	optimize_pictures.sh --in-place $@
```

This rule uses some make-specific patterns to process all files in an `images/` directory. For each file in the `images/` directory, make is going to:

1. Copy the file to a directory named `build/images/`: `cp $< $@`
2. Compress the file in-place using our program `optimize_pictures.sh`: `optimize_pictures.sh --in-place $@`

The strength of `make` is that it automatically detects files that were already processed.

## Our makefiles

To use make, you need to install the program `GNU make`, then to call `make` from the shell in a directory containing a file named `Makefile`. The makefile contains the rules make has to follow and dependencies required to build a given file. For example, for us, to export an HTML or PDF document from our source files, we first need to compress pictures and videos.

You can find our example makefiles in this directory. They are here as examples, and you will need to adapt them to your projects.
