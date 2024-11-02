import std/[algorithm, os, strutils, sugar, tables, sets]

const
  EXT_XML = ".xml"
  EXT_SVG = ".svg"
  DIR_THIS = currentSourcePath.parentDir()
  DIR_GODOT_MODULES = DIR_THIS / "godot/modules"

const CACHE_GODOT_BUILTIN_CLASSES* = static:
  var result: seq[string]

  echo "Caching Godot builtin classes..."

  const DIR_GODOT_DOCUMENTATION = DIR_THIS / "godot/doc/classes"
  for node in walkDir(DIR_GODOT_DOCUMENTATION):
    if node.kind == pcFile and node.path.toLower.endsWith(EXT_XML):
      result.add node.path.splitFile.name

  for path in walkDirRec(DIR_GODOT_MODULES):
    if "doc_classes" in path and path.toLower.endsWith(EXT_XML):
      result.add path.splitFile.name
  result.sorted((x, y) => cmp(x.len, y.len), Descending)

const CACHE_GODOT_ICONS* = block:
  var result: Table[string, string]

  echo "Caching Godot icons..."

  const DIR_GODOT_ICONS = DIR_THIS / "godot/editor/icons"
  for node in walkDir(DIR_GODOT_ICONS):
    if node.kind == pcFile and node.path.toLower.endsWith(EXT_SVG):
      result[node.path.splitFile.name] = staticRead(node.path.replace(DIR_THIS, ""))

  for path in walkDirRec(DIR_GODOT_MODULES):
    if "icons" in path and path.toLower.endsWith(EXT_SVG):
      result[path.splitFile.name] = staticRead(path.replace(DIR_THIS, ""))

  result

const CACHE_EDITOR_ICONS* = block:
  var icons_seq = newSeq[string]()
  echo "Caching editor icons..."

  for icon in CACHE_GODOT_ICONS.keys:
    if icon notin CACHE_GODOT_BUILTIN_CLASSES:
      icons_seq.add(icon)

  icons_seq.toHashSet()

echo "Done caching."
const CACHE_BLACKLIST* = ["2D", "3D", "Godot", "GDScript", "GDQuest", "UI"].sorted(
  (x, y) => cmp(x.len, y.len), Descending
)
