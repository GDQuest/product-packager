# GDSchool build

![Plugin banner image](./img/product-packager.png)

This repository, formerly Product Packager, is a work-in-progress static site builder for the [GDSchool](http://school.gdquest.com/) Learning Management System (LMS) platform.

The program is written in the [Nim programming language](http://nim-lang.org) and it:

- Preprocesses MDX files
- Parses GDScript code symbols and code regions to include in lessons
- Extracts data from Godot and image files

It's being extended to parse a simplified flavor of MDX that will:

- Create an Abstract Syntax Tree (AST) for MDX files
- Provide an API to transform the AST
- Render it as HTML and web components

<details>
  <summary>Why make your own LMS platform?</summary>

  Almost all LMS platforms out there, proprietary or open source, are designed to offer a generic experience and focus on video, which doesn't match what we make. We want to be able to innovate and have full control over the learning experience and platform. We've already used off-the-shelf platforms but always found ourselves limited, either by the complexity of their codebase or the lack of customization options.

</details>
<details>
  <summary>Why make your own static site builder?</summary>

  After working on many web projects and trying to build our web with several web frameworks, we find that for the most part, they are too complex and slow, and you pay a high technical debt for the initial convenience and boost in development speed.

  By coding our own tools, we can control the entire process and optimize it for our specific needs. We've already lost weeks, if not months of development time working around the quirks of popular frameworks.

  That's the kind of time it takes to write our own tools from scratch.

  It's an investment that pays off in the long run. Also, the fully fledged website build system only requires a couple thousand lines of code and builds a website with thousands of pages from scratch within seconds on a single thread. No need for complex dependency graphs.

</details>

## Support us

Our work on Free Software is sponsored by our [Godot game creation courses](https://gdquest.com/). Consider getting one to support us!

_If you like our work, please star the repository! This helps more people find it._

## Join the community

- You can join the GDQuest community and come chat with us on [Discord](https://discord.gg/CHYVgar)
- For quick news, follow us on [Twitter](https://twitter.com/nathangdquest)
- We release video tutorials and major updates on [YouTube](https://youtube.com/c/gdquest)
