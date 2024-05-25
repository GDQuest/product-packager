import std/
  [ algorithm
  , os
  , strutils
  , sugar
  , tables
  ]


const
  EXT_XML = ".xml"
  EXT_SVG = ".svg"
  DIR_ROOT = "src/md"
  DIR_GODOT_ICONS = "godot/editor/icons"
  DIR_GODOT_MODULES = "godot/modules"
  DIR_GODOT_DOC_CLASSES = "godot/doc/classes"
  
  CACHE_GODOT_BUILTIN_CLASSES* = block:
    var result: seq[string]

    for node in walkDir(DIR_ROOT / DIR_GODOT_DOC_CLASSES):
      if node.kind == pcFile and node.path.toLower.endsWith(EXT_XML):
        result.add node.path.splitFile.name

    for path in walkDirRec(DIR_ROOT / DIR_GODOT_MODULES):
      if "doc_classes" in path and path.toLower.endsWith(EXT_XML):
        result.add path.splitFile.name
    result.sorted((x, y) => cmp(x.len, y.len), Descending)

  CACHE_GODOT_ICONS* = block:
    var result: Table[string, string]

    for node in walkDir(DIR_ROOT / DIR_GODOT_ICONS):
      if node.kind == pcFile and node.path.toLower.endsWith(EXT_SVG):
        result[node.path.splitFile.name] = staticRead(node.path.replace(DIR_ROOT, ""))

    for path in walkDirRec(DIR_ROOT / DIR_GODOT_MODULES):
      if "icons" in path and path.toLower.endsWith(EXT_SVG):
        result[path.splitFile.name] = staticRead(path.replace(DIR_ROOT, ""))

    result

  CACHE_BLACKLIST* = [ "2D"
                     , "3D"
                     , "Godot"
                     , "GDScript"
                     , "GDQuest"
                     , "UI"
                     ].sorted((x, y) => cmp(x.len, y.len), Descending)
