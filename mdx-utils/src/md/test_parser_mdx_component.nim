import unittest
import parser_mdx_component

proc testBlockParsing(source: string): seq[BlockToken] =
  let tokens = parser_mdx_component.tokenize(source)
  var scanner = parser_mdx_component.TokenScanner(
    tokens: tokens,
    current: 0,
    source: source
  )
  return parser_mdx_component.parseMdxDocumentBlocks(scanner)

suite "MDX Block Parser Tests":
  test "Parse simple MDX component":
    const source = """
Hello there!

<Component src="path" title="Title">
Content here.
</Component>
"""
    let blocks = testBlockParsing(source)

    check:
      blocks.len == 1
      blocks[0].kind == MdxComponent
      blocks[0].source[blocks[0].name.start..<blocks[0].name.end] == "Component"

  test "Parse code block":
    const source = """
# Document heading

```gdscript
extends Node

func _ready():
    print("Hello, World!")
```

Some more text.
"""
    let blocks = testBlockParsing(source)

    check:
      blocks.len == 1
      blocks[0].kind == CodeBlock
      blocks[0].source[blocks[0].language.start..<blocks[0].language.end] == "gdscript"

  test "Parse self-closing MDX component":
    const source = """
Content here.

<SelfClosingComponent src="path" title="Title" />

More content.
"""
    let blocks = testBlockParsing(source)

    check:
      blocks.len == 1
      blocks[0].kind == SelfClosingMdxComponent
      blocks[0].source[blocks[0].name.start..<blocks[0].name.end] == "SelfClosingComponent"

  test "Parse mixed MDX and code blocks":
    const source = """
# Document heading

Text here.

<Component paths={["path1", "path2"]} />

More text with a code example:

```gdscript
extends Sprite2D

var health: int = 100
```

Followed by text.
"""
    let blocks = testBlockParsing(source)

    check:
      blocks.len == 2
      blocks[0].kind == SelfClosingMdxComponent
      blocks[0].source[blocks[0].name.start..<blocks[0].name.end] == "Component"
      blocks[1].kind == CodeBlock
      blocks[1].source[blocks[1].language.start..<blocks[1].language.end] == "gdscript"

  test "Component name must start with capital letter":
    const source = """
<lowercase>
Should not parse as component
</lowercase>
"""
    let blocks = testBlockParsing(source)
    check blocks.len == 0

  test "Parse nested attributes":
    const source = """
<Component prop={["value1", "value2"]} nested={{ key: "value" }}>
Content
</Component>
"""
    let blocks = testBlockParsing(source)

    check:
      blocks.len == 1
      blocks[0].kind == MdxComponent
      blocks[0].source[blocks[0].name.start..<blocks[0].name.end] == "Component"
