import std/
  [ algorithm
  , os
  , strutils
  , sugar
  , tables
  ]


const
  XML_EXT = ".xml"
  SVG_EXT = ".svg"
  DIR_GODOT_ICONS = "../../godot/editor/icons"
  DIR_GODOT_DOC_CLASSES = "../../godot/doc/classes"
  DIR_GODOT_MODULES = "../../godot/modules"

  CACHE_GODOT_BUILTIN_CLASSES* = block:
    var result: seq[string]

    for node in walkDir(DIR_GODOT_DOC_CLASSES, checkDir = true):
      if node.kind == pcFile and node.path.toLower.endsWith(XML_EXT):
        result.add node.path.splitFile.name

    for path in walkDirRec(DIR_GODOT_MODULES, checkDir = true):
      if "doc_classes" in path and path.toLower.endsWith(XML_EXT):
        result.add path.splitFile.name

    result.sorted((x, y) => cmp(x.len, y.len), Descending)

  CACHE_GODOT_ICONS* = block:
    var result: Table[string, string]

    for node in walkDir(DIR_GODOT_ICONS, checkDir = true):
      if node.kind == pcFile and node.path.toLower.endsWith(SVG_EXT):
        result[node.path.splitFile.name] = staticRead(node.path)

    for path in walkDirRec(DIR_GODOT_MODULES, checkDir = true):
      if "icons" in path and path.toLower.endsWith(SVG_EXT):
        result[path.splitFile.name] = staticRead(path)

    result
