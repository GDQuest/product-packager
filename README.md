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
- Compress and resize png and jpg images using [imagemagick](https://www.imagemagick.org/).
- Compress and resize videos with [FFMpeg](https://ffmpeg.org/).

## How to use

Product packager is a modular set of tools to help process files and package products. You can find them in the `programs/` directory.

To package complete products, we use `make`, a program to create incremental builds and process files based on sets of rules. For more information, see [the makefiles directory's README](makefiles/README.md). There, you can also find our example make files.

You can use these tools individually. For example, here are some example commands I would use to compress pictures and videos in a directory using my favorite shell, [fish](https://fishshell.com/):

```sh
optimize_pictures.sh --output output_directory --resize 1280:-1\> -- pictures/*.{jpg,png}
optimize_videos.sh --output output_directory videos/*.mp4
```

Other commands help you with git repositories and projects made with the Godot game engine:

```sh
git_checkout_repositories.sh (find godot -type d -name .git)
package_godot_projects.sh ./godot/ ./dist/
```

We also have a program to render markdown documents to PDF or standalone HTML using [pandoc](https://pandoc.org/):

```sh
convert_markdown.sh --css pandoc.css --output-path dist content/**.md
```

I also use the tools above to compress files before uploading them, or to share documents online.

Run any program with the `--help` option to learn to use it. Also, if you find a bug, you can run tools with the `-d` or `--dry-run` option to output debug information. Please copy and paste that output to any bug you report in the [issues tab](issues).

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
