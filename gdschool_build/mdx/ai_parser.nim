import strutils, sequtils, tables

# ... (MDXTokenType, MDXToken, MDXLexer, and tokenizer functions from the previous response) ...

type
  MDXNodeKind = enum
    TextNode
    CodeBlockNode
    InlineCodeNode
    BoldNode
    ItalicNode
    LinkNode
    HeadingNode  # Not implemented in the tokenizer yet, but reserved
    ParagraphNode # Not implemented in the tokenizer yet, but reserved
    DocumentNode

type
  MDXNode = object
    kind: MDXNodeKind
    value: string
    children: seq[MDXNode]
    line: int
    col: int

proc newMDXNode(kind: MDXNodeKind, value: string = "", line: int = 0, col: int = 0): MDXNode =
  MDXNode(kind: kind, value: value, children: @[], line: line, col: col)


proc parseLink(tokens: var seq[MDXToken], pos: var int): MDXNode =
  let startToken = tokens[pos]
  inc(pos)  # Consume '['

  let textNode = newMDXNode(MDXNodeKind.TextNode, tokens[pos].value, tokens[pos].line, tokens[pos].col)
  inc(pos) # Consume text
  inc(pos) # Consume ']'

  inc(pos) # Consume '('

  let urlNode = newMDXNode(MDXNodeKind.TextNode, tokens[pos].value, tokens[pos].line, tokens[pos].col)
  inc(pos) # Consume url
  inc(pos) # Consume ')'

  let linkNode = newMDXNode(MDXNodeKind.LinkNode, "", startToken.line, startToken.col)
  linkNode.children.add(textNode)
  linkNode.children.add(urlNode)

  return linkNode

proc parseBold(tokens: var seq[MDXToken], pos: var int): MDXNode =
    let startToken = tokens[pos]
    inc(pos) # Consume "**"
    let textNode = newMDXNode(MDXNodeKind.TextNode, tokens[pos].value, tokens[pos].line, tokens[pos].col)
    inc(pos) # Consume text
    inc(pos) # Consume "**"
    let boldNode = newMDXNode(MDXNodeKind.BoldNode, "", startToken.line, startToken.col)
    boldNode.children.add(textNode)
    return boldNode

proc parseItalic(tokens: var seq[MDXToken], pos: var int): MDXNode =
    let startToken = tokens[pos]
    inc(pos) # Consume "*"
    let textNode = newMDXNode(MDXNodeKind.TextNode, tokens[pos].value, tokens[pos].line, tokens[pos].col)
    inc(pos) # Consume text
    inc(pos) # Consume "*"
    let italicNode = newMDXNode(MDXNodeKind.ItalicNode, "", startToken.line, startToken.col)
    italicNode.children.add(textNode)
    return italicNode


proc parseCodeBlock(tokens: var seq[MDXToken], pos: var int): MDXNode =
  let startToken = tokens[pos]
  inc(pos) # Consume "```"

  var code = ""
  while tokens[pos].tokenType != MDXTokenType.CodeBlockEnd:
    code.add(tokens[pos].value & "\n") # Preserve newlines within code blocks
    inc(pos)
  inc(pos) # Consume "```"

  return newMDXNode(MDXNodeKind.CodeBlockNode, code, startToken.line, startToken.col)

proc parseInlineCode(tokens: var seq[MDXToken], pos: var int): MDXNode =
  let startToken = tokens[pos]
  inc(pos) # Consume "`"
  let code = tokens[pos].value
  inc(pos) # Consume code
  inc(pos) # Consume "`"
  return newMDXNode(MDXNodeKind.InlineCodeNode, code, startToken.line, startToken.col)


proc parseText(tokens: var seq[MDXToken], pos: var int): MDXNode =
  let text = tokens[pos].value
  let line = tokens[pos].line
  let col = tokens[pos].col
  inc(pos)
  return newMDXNode(MDXNodeKind.TextNode, text, line, col)

proc parse(tokens: seq[MDXToken]): MDXNode =
  var pos = 0
  let root = newMDXNode(MDXNodeKind.DocumentNode)

  while pos < len(tokens):
    case tokens[pos].tokenType:
      of MDXTokenType.Text:
        root.children.add(parseText(tokens, pos))
      of MDXTokenType.LinkStart:
        root.children.add(parseLink(tokens, pos))
      of MDXTokenType.BoldStart:
        root.children.add(parseBold(tokens, pos))
      of MDXTokenType.ItalicStart:
        root.children.add(parseItalic(tokens, pos))
      of MDXTokenType.CodeBlockStart:
        root.children.add(parseCodeBlock(tokens, pos))
      of MDXTokenType.InlineCode:
        root.children.add(parseInlineCode(tokens, pos))
      of MDXTokenType.Newline:
        inc(pos) # Skip newlines for now (handle paragraphs later)
      else:
        inc(pos) # Skip unknown tokens for now (improve error handling later)

  return root

# Example usage:
let mdxInput = """
# My Document

This is some *italic* text and some **bold** text.  Here is a [link](https://example.com) and some `inline code`.

```nim
echo "Hello, world!"""

when isMainModule:
  let lexer = newMDXLexer(mdxInput)
  let tokens = tokenize(lexer)

  for token in tokens:
    echo token

  let ast = parse(tokens)

  proc printAST(node: MDXNode, indent: int = 0) =
    echo indent * "  ", node.kind, ": ", node.value

  for child in ast.children:
    printAST(child, indent + 1)

  printAST(ast)

