# Automate product builds with tup and make

To build course releases (render videos, export documents...), we use [GNU make](https://www.gnu.org/software/make/) alongside [Tup](http://gittup.org/tup/). They're both programs to build files based on a set of rules and dependencies. You need both programs installed to use these build rules:

```sh
sudo apt install make tup
```

Whenever we update a lesson, modify a video edit, or add a new file, all we have to do is to run `make` and the programs find and rebuild only the files that changed.

Here's a description of the files:

- `Makefile` allows you to build the project or clean the build directories with `make` and `make clean`, respectively. It delegates processing on individual files to `tup`.
- `Tuprules.tup` defines some variables, mostly paths to the programs in product packager and commands to run to build the project. Each member of the team can have the programs in a different folder thanks to that.
- `Tupfile.ini` is an empty file for us. It's required for tup to run. In it, you can configure `tup` to only use some cores, or to keep running even with errors.
- `Tupfile.SUBDIR` gets copied to sub-directories in your project by `make` and tells `tup` how to transform files found there.
