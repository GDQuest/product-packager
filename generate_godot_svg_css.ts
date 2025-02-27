/**
 * This program bundles the SVG icons and classes from the Godot source code into a single
 * executable file. It then outputs a css file and a folder filled with SVG files to use
 * on websites.
 *
 * Creates the following files in the current directory:
 *
 * - godot_icons.css
 * - icons/godot/*.svg
 */

import { CACHE_GODOT_ICONS } from "./preprocessor/godot_cached_data.ts";
import { join } from "https://deno.land/std/path/mod.ts";
import { ensureDirSync, existsSync } from "https://deno.land/std/fs/mod.ts";

// These attributes will make the icons scalable and make them work with a single class name (i-gd-*)
const css: string = `[class^="i-gd-"],
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
`;

if (Deno.args.length !== 1) {
  console.error(
    "Error: Please provide exactly one argument - the root directory path of GDSchool.",
  );
  console.error(
    "This program outputs icon css and SVG files directly to the relevant folders in GDSchool's codebase.",
  );
  console.error(`Usage: ${Deno.execPath()} <output_path>`);
  Deno.exit(1);
}

const outputPath = Deno.args[0];
if (!existsSync(outputPath)) {
  console.error(
    `Error: The desired output directory does not exist: ${outputPath}`,
  );
  Deno.exit(1);
}

const stylesDir = join(outputPath, "src", "styles");
const iconsDir = join(outputPath, "public", "icons", "godot");

for (const directory of [stylesDir, iconsDir]) {
  if (!existsSync(directory)) {
    console.error(`Error: The directory does not exist: ${directory}`);
    console.error(
      "Are you sure you provided the correct path to GDSchool's root directory?",
    );
    Deno.exit(1);
  }
}

let cssContent = css;
for (const godotClassName of Object.keys(CACHE_GODOT_ICONS)) {
  cssContent += `.i-gd-${godotClassName} { background-image: url(/icons/godot/${godotClassName}.svg); }\n`;
}

const scssPath = join(stylesDir, "godot_icons.scss");
Deno.writeTextFileSync(scssPath, cssContent);
console.log(`Wrote ${scssPath}`);

// Processing and writing SVG files
console.log(`Writing SVG files to ${iconsDir}...`);

const COLORS_MAP: Record<string, string> = {
  "#8da5f3": "#6984db", // Node2D blue
  "#fc7f7f": "#ff6969", // Node3D red
  "#8eef97": "#6dde78", // Control green
  "#e0e0e0": "#c0bdbd", // Node grey
};

// Ensure the icons directory exists
ensureDirSync(iconsDir);

for (const godotClassName of Object.keys(CACHE_GODOT_ICONS)) {
  let svgData = CACHE_GODOT_ICONS[godotClassName];
  for (const [key, value] of Object.entries(COLORS_MAP)) {
    svgData = svgData.replaceAll(key, value);
  }
  Deno.writeTextFileSync(join(iconsDir, `${godotClassName}.svg`), svgData);
}

console.log("Done!");
