## This script downloads a copy of the Godot engine source file and extracts data used by GDSchool from it:
##
## - The list of built-in classes
## - SVG icon files
##
# cache_generator.nim
import std/[algorithm, os, strutils, sugar, tables, sets]

const
  EXT_XML = ".xml"
  EXT_SVG = ".svg"

proc main() =
  # Find the root of the repository (looks for the .git folder)
  # The godot data will be copied there.
  let repositoryRootDir = block:
    var currentDir = currentSourcePath().parentDir()
    while not dirExists(currentDir / ".git"):
      let parentDir = currentDir.parentDir()
      if parentDir == currentDir: # We've hit the root
        raise newException(
          OSError,
          "Could not find the .git directory repository in the parent directories",
        )
      currentDir = parentDir
    currentDir
  let godotDocPath = repositoryRootDir / "godot/doc/classes"
  let godotModulesPath = repositoryRootDir / "godot/modules"
  let godotIconsPath = repositoryRootDir / "godot/editor/icons"
  let outputPath =
    repositoryRootDir / "gdschool_build/preprocessor/godot_cached_data.nim"

  # Add, clone, or update Godot repository if needed
  if not dirExists("godot"):
    let doesRemoteExist = execShellCmd("git remote get-url godot > /dev/null") == 0
    if not doesRemoteExist:
      const CMD_ADD_REMOTE =
        "git remote add -f -t master --no-tags godot https://github.com/godotengine/godot.git"
      echo "Adding remote for Godot's master branch: "
      echo CMD_ADD_REMOTE
      let errorCode = execShellCmd(CMD_ADD_REMOTE)
      if errorCode != 0:
        raise newException(OSError, "Failed to add remote for Godot's master branch")

    echo "Copying relevant Godot data to the repository root..."
    let readClassesResult = execShellCmd(
      "git read-tree --prefix=godot/doc/classes -u godot/master:doc/classes"
    )
    if readClassesResult != 0:
      raise newException(OSError, "Failed to read doc/classes tree")

    let readIconsResult = execShellCmd(
      "git read-tree --prefix=godot/editor/icons -u godot/master:editor/icons"
    )
    if readIconsResult != 0:
      raise newException(OSError, "Failed to read editor/icons tree")

    let readModulesResult =
      execShellCmd("git read-tree --prefix=godot/modules -u godot/master:modules")
    if readModulesResult != 0:
      raise newException(OSError, "Failed to read modules tree")

  echo "Reading Godot data from engine source files..."
  var builtinClasses: seq[string]
  for node in walkDir(godotDocPath):
    if node.kind == pcFile and node.path.toLower.endsWith(EXT_XML):
      builtinClasses.add node.path.splitFile().name

  for path in walkDirRec(godotModulesPath):
    if "doc_classes" in path and path.toLower.endsWith(EXT_XML):
      builtinClasses.add path.splitFile().name

  builtinClasses.sort((x, y) => cmp(x.len, y.len), Descending)

  # Gather icons
  var icons: Table[string, string]
  for node in walkDir(godotIconsPath):
    if node.kind == pcFile and node.path.toLower.endsWith(EXT_SVG):
      icons[node.path.splitFile.name] = readFile(node.path)

  for path in walkDirRec(godotModulesPath):
    if "icons" in path and path.toLower.endsWith(EXT_SVG):
      icons[path.splitFile.name] = readFile(path)

  # Create editor icons set
  var editorIcons = initHashSet[string]()
  for icon in icons.keys:
    if icon notin builtinClasses:
      editorIcons.incl(icon)

  echo "Generating nim cache file..."
  var output =
    """## Cached data extracted from the Godot engine source files.
##
## This file is used by the GDSchool preprocessor to check material against the
## Godot engine's built-in classes and icons. Run the script
## update_godot_data.nim to update.
##
## AUTO-GENERATED GODOT CACHE FILE. DO NOT EDIT MANUALLY.
import std/[tables, sets]

"""

  # Write builtin classes
  output.add "const CACHE_GODOT_BUILTIN_CLASSES* = [\n"
  for class in builtinClasses:
    output.add "  \"" & class & "\",\n"
  output.add "].toHashSet()\n\n"

  # Write icons table
  output.add "const CACHE_GODOT_ICONS* = {\n"
  for name, content in icons:
    # Escape special characters in the SVG content
    let escapedContent = content.multiReplace({"\"": "\\\"", "\n": "\\n"})
    output.add "  \"" & name & "\": \"" & escapedContent & "\",\n"
  output.add "}.toTable()\n\n"

  # Write editor icons set
  output.add "const CACHE_EDITOR_ICONS* = [\n"
  for icon in editorIcons:
    output.add "  \"" & icon & "\",\n"
  output.add "].toHashSet()\n\n"

  writeFile(outputPath, output)
  echo "Cache file generated successfully!"

when isMainModule:
  main()
