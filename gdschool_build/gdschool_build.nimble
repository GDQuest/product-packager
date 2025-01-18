# Package

version     = "2.0.0"
author      = "GDQuest"
description = "Preprocessor and build system for GDQuest's GDSchool LMS platform"
license     = "MIT"
srcDir      = "src"
namedBin    =
  { "gdschool_build": "bin/gdschool_build",
    "generate_godot_svg_css": "bin/generate_godot_svg_css"
  }.toTable

# Dependencies

requires "nim >= 2.2.0"
requires "fuzzy >= 0.1.0"
requires "itertools >= 0.4.0"
