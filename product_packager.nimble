# Package

version     = "0.2.0"
author      = "razcore-rad"
description = "Suite of utilities for formatting, linting and building GDQuest courses from Markdown files and Godot projects"
license     = "MIT"
srcDir      = "src"
namedBin    =
  { "format": "bin/gdquest-format"
  , "buildcourse": "bin/gdquest-build-course"
  , "preprocessgdschool": "bin/gdschool-preprocess-course"
  }.toTable

# Dependencies

requires "nim >= 1.6.4"
requires "fuzzy >= 0.1.0"
requires "honeycomb >= 0.1.1"
requires "itertools >= 0.4.0"
