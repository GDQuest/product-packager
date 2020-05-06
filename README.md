# GDQuest Product Packager

Product Packager is a tool to help creators package and publish their tutorial series, courses, tools, and other products to platforms like [Gumroad](https://gumroad.com/), [Itch.io](https://itch.io/), or [Mavenseed](https://mavenseed.com/).

It is currently **early in development** and **not suitable for production use**.

To get notified when the first stable release is out, click the GitHub Watch button and select "Releases only".

## Features

The programs in this repository can already:

- Process and package Godot projects to distribute their source code.
- Auto checkout git repositories to master.
- Render Blender video project with our [Blender multi-threaded video rendered](https://github.com/GDQuest/blender-sequencer-multithreaded-render).
- Render source documents to self-contained HTML or PDF with Pandoc.
- Compress videos with FFMpeg.

## How to use

_Last update on May 5th 2020._

Product packager is a modular set of tools to package products. You can find them in the `programs/` directory.

To package a complete product, you can call these tools one after the other. Here is how I currently package one of our [game creation courses](https://gdquest.mavenseed.com/) using the [fish shell](https://fishshell.com/):

```sh
# After finishing each course chapter, compressing pictures and videos to reduce download size
optimize_pictures.sh content/chapter-x/**.{jpg,png}
optimize_videos.sh content/chapter-x/**.mp4

# When preparing a new, clean release
rm -rf ./dist/
git_checkout_repositories.sh (find godot -type d -name .git)
package_godot_projects.sh ./godot/ ./dist/
convert_markdown.sh **.md ./dist/
```

I also use the tools above to compress files before uploading them, or to share documents online.

Run any program with the `--help` option to learn to use it. Also, if you find a bug, you can run tools with the `-d` or `--dry-run` option to output debug information. Please copy and paste that output to any bug you report in the [issues tab](issues).

## Using `product_packager`

⚠ The program in the top directory, `product_packager`, is a work-in-progress. It's not ready to use. The goal of this program is to provide a simple command to automatically package products for you.

Product packager expects some particular directory structure to work. We designed it to support exporting a list of files, but also to produce online courses like the ones we have on [our mavenseed website](https://gdquest.mavenseed.com/).

- The `content/` directory should contain your course's chapters, sections, or parts.
- The `godot/` directory should contain your godot projects, each one in a sub-directory.

You can [customize](#customizing-the-project-directories) these directory paths.

Here is the source directory structure of our course [Code a Professional 3D Character with Godot](https://gdquest.mavenseed.com/courses/code-a-professional-3d-character-with-godot):

```sh
.
├── content
│   ├── 00.course-introduction
│   ├── 01.state-machine
│   ├── 02.character-movement
│   ├── 03.camera-rig
│   └── conclusion
├── godot
│   ├── 01.the-state-machine
│   ├── 02.character-movement
│   ├── 03.the-camera-rig
│   ├── final
│   ├── start
│   └── tutorial
```

Each sub-directory in `content/` corresponds to a separate chapter in the final course.

### Customizing the project directories

You can customize the directories you want to use using the `$dir_*` variables in the program:

```sh
dir_dist="dist"
dir_content="content"
dir_godot="godot"
```

Note that the directory path should not end with a "/". For example, if you want your source content to be in `./project/src/`:

```sh
dir_content="project/src"
```

## Contributing

If you encounter a bug or you have an idea to improve the tool, please [open an issue](https://github.com/GDQuest/product-packager/issues).

If you want to contribute to the project, for instance, by fixing a bug or adding a feature, check out our [Contributor's guidelines](https://www.gdquest.com/docs/guidelines/contributing-to/gdquest-projects/).

Also, please use [ShellCheck](https://www.shellcheck.net/) to lint your code and ensure it's POSIX-compliant.

Pull requests and code reviews are much welcome. You can share your feedback and POSIX shell programming tips in the issues tab, or by sending me a message (see below).

## Support us

Our work on Free Software is sponsored by our [Godot game creation courses](https://gdquest.mavenseed.com/). Consider getting one to support us!

_If you like our work, please star the repository! This helps more people find it._

## Join the community

- You can join the GDQuest community and come chat with us on [Discord](https://discord.gg/CHYVgar)
- For quick news, follow us on [Twitter](https://twitter.com/nathangdquest)
- We release video tutorials and major updates on [YouTube](https://youtube.com/c/gdquest)
