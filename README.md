# GDQuest Product Packager

![Plugin banner image](./img/product-packager.png)

Product Packager is a set of CLI tools to help GDQuest in creating their tutorial series, courses and other products.

## Features

This repository contains utilities for our internal build system to create courses.

It does things such as:

- Auto-formats [MDX](https://mdxjs.com) files.
- Preprocesses MDX files:
    - You can use templates in MDX to link to other documents `{{ link }}`, include content from code files `{{ include Filename.gd anchor_name }}`, or generate a table of contents with `{{ contents }}`.
    - It appends Godot icon images before detected class names.
- Compress and resize png and jpg images using [imagemagick](https://www.imagemagick.org/).
- Compress and resize videos with [FFMpeg](https://ffmpeg.org/).
- Strip documents to translate from code, to count words to translate.

## How to use

Product packager is a modular set of tools to help process files and package products. You can find them in their respective directories.

You can use these tools individually. For example, here are some example commands I would use to compress pictures and videos in a directory using my favorite shell, [fish](https://fishshell.com/):

```sh
optimize_pictures.sh --output output_directory --resize 1280:-1\> -- pictures/*.{jpg,png}
optimize_videos.sh --output output_directory videos/*.mp4
```

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
