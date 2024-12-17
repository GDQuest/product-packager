# Package

version     = "1.0.0"
author      = "GDQuest"
description = "Suite of utilities for GDQuest courses from Markdown files and Godot projects"
license     = "MIT"
srcDir      = "src"
namedBin    =
  { "format_lesson_content": "bin/gdschool-format-mdx"
  , "gdschool_preprocess_mdx": "bin/gdschool-preprocess-mdx"
  , "generate_godot_svg_css": "bin/gdschool-godot-svg-css"
  }.toTable

# Dependencies

requires "nim >= 1.6.4"
requires "fuzzy >= 0.1.0"
requires "honeycomb >= 0.1.1"
requires "itertools >= 0.4.0"
