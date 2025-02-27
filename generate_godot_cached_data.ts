#!/usr/bin/env deno --allow-run --allow-read --allow-write
/**
 * This script downloads a copy of the Godot engine source file and extracts data used by GDSchool from it:
 *
 * - The list of built-in classes
 * - SVG icon files
 */

const EXT_XML = ".xml";
const EXT_SVG = ".svg";

import {
  join,
  dirname,
  basename,
  extname,
} from "https://deno.land/std/path/mod.ts";
import { exists } from "https://deno.land/std/fs/exists.ts";
import { walk, WalkEntry } from "https://deno.land/std/fs/walk.ts";

/**
 * Main function to extract and cache Godot data
 */
const main = async (): Promise<void> => {
  // Find the root of the repository (looks for the .git folder)
  // The godot data will be copied there.
  const repositoryRootDir = await (async (): Promise<string> => {
    let currentDir = dirname(new URL(import.meta.url).pathname);
    while (!(await exists(join(currentDir, ".git")))) {
      const parentDir = dirname(currentDir);
      if (parentDir === currentDir) {
        // We've hit the root
        throw new Error(
          "Could not find the .git directory repository in the parent directories",
        );
      }
      currentDir = parentDir;
    }
    return currentDir;
  })();

  const godotDocPath = join(repositoryRootDir, "godot/doc/classes");
  const godotModulesPath = join(repositoryRootDir, "godot/modules");
  const godotIconsPath = join(repositoryRootDir, "godot/editor/icons");
  const outputPath = join(
    repositoryRootDir,
    "gdschool_build/preprocessor/godot_cached_data.ts",
  );

  // Add, clone, or update Godot repository if needed
  if (!(await exists("godot"))) {
    const doesRemoteExist =
      (
        await Deno.run({
          cmd: ["git", "remote", "get-url", "godot"],
          stdout: "null",
          stderr: "null",
        }).status()
      ).code === 0;

    if (!doesRemoteExist) {
      const CMD_ADD_REMOTE =
        "git remote add -f -t master --no-tags godot https://github.com/godotengine/godot.git";
      console.log("Adding remote for Godot's master branch: ");
      console.log(CMD_ADD_REMOTE);

      const process = Deno.run({
        cmd: CMD_ADD_REMOTE.split(" "),
      });
      const status = await process.status();

      if (status.code !== 0) {
        throw new Error("Failed to add remote for Godot's master branch");
      }
    }

    console.log("Copying relevant Godot data to the repository root...");

    const readClassesProcess = Deno.run({
      cmd: [
        "git",
        "read-tree",
        "--prefix=godot/doc/classes",
        "-u",
        "godot/master:doc/classes",
      ],
    });
    const readClassesStatus = await readClassesProcess.status();

    if (readClassesStatus.code !== 0) {
      throw new Error("Failed to read doc/classes tree");
    }

    const readIconsProcess = Deno.run({
      cmd: [
        "git",
        "read-tree",
        "--prefix=godot/editor/icons",
        "-u",
        "godot/master:editor/icons",
      ],
    });
    const readIconsStatus = await readIconsProcess.status();

    if (readIconsStatus.code !== 0) {
      throw new Error("Failed to read editor/icons tree");
    }

    const readModulesProcess = Deno.run({
      cmd: [
        "git",
        "read-tree",
        "--prefix=godot/modules",
        "-u",
        "godot/master:modules",
      ],
    });
    const readModulesStatus = await readModulesProcess.status();

    if (readModulesStatus.code !== 0) {
      throw new Error("Failed to read modules tree");
    }
  }

  console.log("Reading Godot data from engine source files...");
  const builtinClasses: string[] = [];

  // Read classes from godotDocPath
  try {
    for await (const entry of Deno.readDir(godotDocPath)) {
      if (entry.isFile && entry.name.toLowerCase().endsWith(EXT_XML)) {
        builtinClasses.push(basename(entry.name, extname(entry.name)));
      }
    }
  } catch (error) {
    console.error(`Error reading from ${godotDocPath}:`, error);
  }

  // Read classes from godotModulesPath
  for await (const entry of walk(godotModulesPath, {
    includeDirs: false,
    exts: [EXT_XML],
  })) {
    if (entry.path.includes("doc_classes")) {
      builtinClasses.push(basename(entry.path, extname(entry.path)));
    }
  }

  // Sort by length in descending order
  builtinClasses.sort((x, y) => y.length - x.length);

  // Gather icons
  const icons: Record<string, string> = {};

  try {
    for await (const entry of Deno.readDir(godotIconsPath)) {
      if (entry.isFile && entry.name.toLowerCase().endsWith(EXT_SVG)) {
        const name = basename(entry.name, extname(entry.name));
        const content = await Deno.readTextFile(
          join(godotIconsPath, entry.name),
        );
        icons[name] = content;
      }
    }
  } catch (error) {
    console.error(`Error reading from ${godotIconsPath}:`, error);
  }

  for await (const entry of walk(godotModulesPath, {
    includeDirs: false,
    exts: [EXT_SVG],
  })) {
    if (entry.path.includes("icons")) {
      const name = basename(entry.path, extname(entry.path));
      const content = await Deno.readTextFile(entry.path);
      icons[name] = content;
    }
  }

  // Create editor icons set
  const editorIcons = new Set<string>();
  for (const icon of Object.keys(icons)) {
    if (!builtinClasses.includes(icon)) {
      editorIcons.add(icon);
    }
  }

  console.log("Generating TypeScript cache file...");
  let output = `/**
 * Cached data extracted from the Godot engine source files.
 *
 * This file is used by the GDSchool preprocessor to check material against the
 * Godot engine's built-in classes and icons. Run the script
 * update_godot_data.ts to update.
 *
 * AUTO-GENERATED GODOT CACHE FILE. DO NOT EDIT MANUALLY.
 */

`;

  // Write builtin classes
  output += "export const CACHE_GODOT_BUILTIN_CLASSES = new Set([\n";
  for (const cls of builtinClasses) {
    output += `  "${cls}",\n`;
  }
  output += "]);\n\n";

  // Write icons table
  output += "export const CACHE_GODOT_ICONS: Record<string, string> = {\n";
  for (const [name, content] of Object.entries(icons)) {
    // Escape special characters in the SVG content
    const escapedContent = content.replace(/"/g, '\\"').replace(/\n/g, "\\n");
    output += `  "${name}": "${escapedContent}",\n`;
  }
  output += "};\n\n";

  output += "export const CACHE_GODOT_CLASSES_WITH_ICONS = new Set([\n";
  for (const cls of builtinClasses) {
    if (cls in icons) {
      // Only include classes that also have icons
      output += `  "${cls}",\n`;
    }
  }
  output += "]);\n\n";

  // Write editor icons set
  output += "export const CACHE_EDITOR_ICONS = new Set([\n";
  for (const icon of editorIcons) {
    output += `  "${icon}",\n`;
  }
  output += "]);\n\n";

  await Deno.writeTextFile(outputPath, output);
  console.log("Cache file generated successfully!");
};

if (import.meta.main) {
  main();
}
