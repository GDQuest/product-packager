## This program bundles the SVG icons and classes from the Godot source code into a single
## executable file. It then outputs a css file and a folder filled with SVG files to use
## on websites.
##
## Creates the following files in the current directory:
##
## - godot_icons.css
## - icons/godot/*.svg

import preprocessor/godot_cached_data
import std/tables
import std/strformat
import std/os
import std/strutils

# These attributes will make the icons scalable and make them work with a single class name (i-gd-*)
var css: string =
  """[class^="i-gd-"],
[class*=" i-gd-"] {
  --icon-background-color: transparent;
  --icon-size: 1.2em;
  background-position: center;
  background-repeat: no-repeat;
  background-size: 100% 100%;
  mask-size: 100% 100%;
  height: var(--icon-size);
  width: var(--icon-size);
  display: inline-block;
  position: relative;
  top: 0.25em;
  margin-inline: 0.1ch;
  background-image: var(--image);
  background-color: var(--icon-background-color);
  outline: 0.15em solid var(--icon-background-color);
  &[class$="-currentColor"],
  &[class*="-currentColor "],
  &.i-gd-use-currentColor {
    background-image: none;
    background-color: currentColor;
    mask-image: var(--image);
    outline: none;
  }
  &.i-gd-as-mask {
    background-color: currentColor;
    mask-image: var(--image);
    outline: none;
  }
}
"""

when isMainModule:
  if paramCount() != 1:
    echo "Error: Please provide exactly one argument - the root directory path of GDSchool."
    echo "This program outputs icon css and SVG files directly to the relevant folders in GDSchool's codebase."
    echo "Usage: ", getAppFilename(), " <output_path>"
    quit(1)

  let outputPath = paramStr(1)
  if not dirExists(outputPath):
    echo "Error: The desired output directory does not exist: ", outputPath
    quit(1)

  let stylesDir = outputPath / "src" / "styles"
  let iconsDir = outputPath / "public" / "icons" / "godot"

  for directory in [stylesDir, iconsDir]:
    if not dirExists(directory):
      echo "Error: The directory does not exist: ", directory
      echo "Are you sure you provided the correct path to GDSchool's root directory?"
      quit(1)

  for godotClassName in godot_cached_data.CACHE_GODOT_ICONS.keys():
    css.add(
      fmt".i-gd-{godotClassName} {{ background-image: url(/icons/godot/{godotClassName}.svg); }}" &
        "\n"
    )
  let scssPath = stylesDir / "godot_icons.scss"
  writeFile(scssPath, css)
  echo "Wrote ", scssPath

  # Processing and writing SVG files
  echo("Writing SVG files to ", iconsDir, "...")

  const COLORS_MAP = {
    "#8da5f3": "#6984db", # Node2D blue
    "#fc7f7f": "#ff6969", # Node3D red
    "#8eef97": "#6dde78", # Control green
    "#e0e0e0": "#c0bdbd", # Node grey
  }.toTable()

  for godotClassName in godot_cached_data.CACHE_GODOT_ICONS.keys():
    var svgData = godot_cached_data.CACHE_GODOT_ICONS[godotClassName]
    for key, value in COLORS_MAP.pairs():
      svgData = svgData.replace(key, value)
    writeFile(iconsDir / fmt"{godotClassName}.svg", svgData)

  echo("Done!")
