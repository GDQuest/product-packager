# GDQuest Product Packager

Product Packager is a tool to help creators package and publish their tutorial series, courses, tools, and other products to platforms like [Gumroad](https://gumroad.com/), [Itch.io](https://itch.io/), or [Mavenseed](https://mavenseed.com/).

It is currently **early in development** and **not suitable for production use**.

To get notified when the first stable release is out, click the GitHub Watch button and select "Releases only".

## Features

The tool can already:

- Process and package Godot projects to distribute their source code.
- Auto checkout git repositories to master.
- Find, organize, and move rendered content files to the output directory.
- Render Blender video project with our [Blender multi-threaded video rendered](https://github.com/GDQuest/blender-sequencer-multithreaded-render).
- Compress videos with ffmpeg.

More is coming quickly and soon. As it's early in development, you need to know about shell code to use it right now. 

Also, the tool is still a single program with all functions in one place. To make it flexible and convenient to use, I plan to:

1. Have each main feature as a separate shell program, so you can use them however you want depending on your needs.
2. Have a `product-packager` program that offers a single command and optional presets to quickly package projects.

## How to use

Run `product_packager --help` to get usage information.

## Contributing

If you encounter a bug or you have an idea to improve the tool, please [open an issue](https://github.com/GDQuest/product-packager/issues).

If you want to contribute to the project, for instance, by fixing a bug or adding a feature, check out our [Contributor's guidelines](https://www.gdquest.com/docs/guidelines/contributing-to/gdquest-projects/).

Also, please use [ShellCheck](https://www.shellcheck.net/) to lint your code and ensure it's POSIX-compliant. 

Pull requests and code reviews are much welcome. You can share your feedback and POSIX shell programming tips in the issues tab, or by sending me a message (see below).

## Support us

Our work on Free Software is sponsored by our [Godot game creation courses](https://gdquest.mavenseed.com/). Consider getting one to support us!

*If you like our work, please star the repository! This helps more people find it.*

## Join the community

- You can join the GDQuest community and come chat with us on [Discord](https://discord.gg/CHYVgar)
- For quick news, follow us on [Twitter](https://twitter.com/nathangdquest)
- We release video tutorials and major updates on [YouTube](https://youtube.com/c/gdquest)
