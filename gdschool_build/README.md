# GDSchool Build

## Overview

The GDSchool Build system is designed to process MDX files, handle file dependencies, and manage the build pipeline. Its purpose is to become a complete build system that can take all the input files for the GDQuest websites and output a mostly static site with some web components.

It includes specialized parsers for GDScript and MDX, as well as support modules for error handling, caching, and image processing.

### Main Components

- **gdschool_build.nim**: The main entry point of the build system that orchestrates the processing of MDX files, handles file dependencies, and manages the build pipeline.
- **settings.nim**: Parses commands, command line arguments, and config files and produces an object with all the program's execution settings.
- **preprocessor/preprocessor.nim**: Transforms content by processing MDX files to replace shortcodes and components. Some of this logic will remain but instead of only preprocessing, in the future, the program should fully parse our input files, transform their AST, and then pass the transformed AST to a rendering function that'll output HTML.

### Specialized Parsers

- **gdscript/parser_gdscript.nim**: A specialized parser for GDScript code that can extract specific code symbols and regions marked with anchor comments to include in tutorials.
- **mdx/parser_mdx.nim**: A work-in-progress parser for MDX documents that should handle both Markdown content and React components. It should produce an AST in the form of a node tree. The goal is not to support Commonmark and MDX, but rather to focus on our specific use case.

### Utilities

- **errors.nim**: This module allows logging errors in a centralized place and outputting them at the end of the build process.
- **cache.nim**: This module caches file paths at the start of the build process for the build system to easily look up code files to parse and include from or content files to process later on.
- **image_size.nim**: This module reads image file headers to extract dimensions from PNG, JPEG, and WebP files.
