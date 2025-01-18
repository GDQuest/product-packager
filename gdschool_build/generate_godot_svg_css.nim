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

when isMainModule:
  # Generating css
  # These attributes will make the icons scalable and make them work with a single class name (i-gd-*)
  var css: string =
    """[class^='i-gd-'], [class*=' i-gd-']{
  background-position: center;
  background-repeat: no-repeat;
  background-size: 100% 100%;
  background-color: transparent;
  height: 1em;
  width: 1em;
}
"""
  for godotClassName in godot_cached_data.CACHE_GODOT_ICONS.keys():
    css.add(
      fmt".i-gd-{godotClassName} {{ background-image: url(/icons/godot/{godotClassName}.svg); }}" &
        "\n"
    )
  writeFile("godot_icons.css", css)
  echo("Wrote godot_icons.css")

  echo(fmt"Writing SVG files to ./icons/godot/...")
  var svgFolder = "icons/godot"
  if not os.dirExists(svgFolder):
    os.createDir(svgFolder)
  for godotClassName in godot_cached_data.CACHE_GODOT_ICONS.keys():
    let svgData = godot_cached_data.CACHE_GODOT_ICONS[godotClassName]
    writeFile(fmt"{svgFolder}/{godotClassName}.svg", svgData)
  echo("Done!")
