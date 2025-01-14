## Parses MDX components contained in MDX files into a tree of nodes.

type
  Range* = object
    ## A range of character indices in a source string or in a sequence of
    ## nodes.
    start*: int
    `end`*: int

  ParseError* = ref object of ValueError
    range*: Range
    message*: string

  AttributeKind = enum
    StringLiteral
    Boolean
    Number
    JSXExpression

  AttributeValue* = ref object
    case kind*: AttributeKind
      of StringLiteral:
        stringValue*: Range
      of Boolean:
        boolValue*: bool
      of Number:
        numberValue*: Range
      of JSXExpression:
        expressionRange*: Range

  MdxAttribute* = object
    range*: Range
    name*: Range
    value*: AttributeValue

  NodeKind* = enum
    MdxComponent
    # Temporary: we'll add more node types later
    MarkdownContent

  Node* = object
    case kind*: NodeKind
    of MdxComponent:
      name*: Range
      attributes*: seq[MdxAttribute]
      isSelfClosing*: bool
      rangeOpeningTag*: Range
      rangeBody*: Range
      rangeClosingTag*: Range
    else:
      discard
    range*: Range
      ## The start and end indices of the node in the source document.
      ## This can be used for error reporting.
    children*: seq[Node]

  ScannerNode = ref object
    nodes: seq[Node]
    currentIndex: int
    source: string
    peekIndex: int


# Forward declaractions to avoid errors with cyclical calls
proc parseNodes(s: ScannerNode): seq[Node]
proc parseMdxComponent(s: ScannerNode): Node
proc parseMarkdownContent(s: ScannerNode): Node

proc charMakeWhitespaceVisible*(c: char): string =
  ## Replaces whitespace characters with visible equivalents.
  case c
  of '\t':
    result = "⇥"
  of '\n':
    result = "↲"
  of ' ':
    result = "·"
  else:
    result = $c

proc getString*(range: Range, source: string): string {.inline.} =
  return source[range.start ..< range.end]

proc currentChar(s: ScannerNode): char {.inline.} =
  s.source[s.currentIndex]

proc peek(s: ScannerNode, offset: int = 0): char {.inline.} =
  ## Returns the current character or a character at the desired offset in the
  ## source string, without advancing the scanner.
  ## Updates the peek index to the current position plus the offset. Call
  ## advanceToPeek() to move the scanner to the peek index.
  s.peekIndex = s.currentIndex + offset
  if s.peekIndex >= s.source.len:
    result = '\0'
  else:
    result = s.source[s.peekIndex]

proc advanceToPeek(s: ScannerNode) {.inline.} =
  ## Advances the scanner to the peek index.
  s.currentIndex = s.peekIndex

proc isPeekSequence(s: ScannerNode, sequence: string): bool {.inline.} =
  ## Returns `true` if the next chars in the scanner match the given sequence.
  for i, expectedChar in sequence:
    if s.peek(i) != expectedChar:
      return false
  return true

proc isAtEnd(s: ScannerNode): bool {.inline.} =
  ## Returns `true` if the scanner has reached the end of the source string.
  s.currentIndex >= s.source.len

proc match(s: ScannerNode, expected: char): bool {.inline.} =
  ## Advances the scanner and returns `true` if the current character matches
  ## the expected one.
  if s.currentIndex >= s.source.len or s.source[s.currentIndex] != expected:
    return false
  s.currentIndex += 1
  return true

proc isAlphanumericOrUnderscore(c: char): bool {.inline.} =
  ## Returns `true` if the character is a letter (lower or uppercase), digit, or
  ## underscore.
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit

proc skipWhitespace(s: ScannerNode) {.inline.} =
  ## Advances the scanner until it finds a non-whitespace character.
  ## Skips spaces, tabs, newlines, and carriage returns.
  while not s.isAtEnd() and s.currentChar in {' ', '\t', '\n', '\r'}:
    s.currentIndex += 1

proc scanIdentifier(s: ScannerNode): Range =
  ## Scans and returns the range of an identifier in the source string,
  ## advancing the scanner to the end of the identifier.
  let start = s.currentIndex
  while not s.isAtEnd() and isAlphanumericOrUnderscore(s.currentChar):
    s.currentIndex += 1
  result = Range(start: start, `end`: s.currentIndex)

proc getCurrentLine(s: ScannerNode): string =
  ## Returns the current line of the scanner without advancing the scanner's current index.
  ## Use this for debugging purposes.
  let initialIndex = s.currentIndex
  # Back up to start of line
  var start = s.currentIndex
  while start > 0 and s.source[start - 1] != '\n':
    start -= 1

  while s.currentChar != '\n' and not s.isAtEnd():
    s.currentIndex += 1

  result = s.source[start ..< s.currentIndex]
  s.currentIndex = initialIndex

proc isUppercaseAscii(c: char): bool {.inline.} =
  return c >= 'A' and c <= 'Z'

proc isMdxComponentStart(s: ScannerNode): bool {.inline.} =
  ## Returns `true` if the scanner is at the start of an MDX component.
  return s.currentChar == '<' and s.peek(1).isUppercaseAscii()

proc isMdxClosingTagStart(s: ScannerNode): bool {.inline.} =
  ## Returns `true` if the scanner is at the start of an MDX component closing tag.
  return s.currentChar == '<' and s.peek(1) == '/'

proc isMdxTagStart(s: ScannerNode): bool {.inline.} =
  ## Returns `true` if the scanner is at the start of an MDX component closing tag.
  return s.currentChar == '<' and (s.peek(1).isUppercaseAscii() or s.peek(1) == '/')

# ---------------- #
#     Markdown     #
# ---------------- #
proc isWhitespace(c: char): bool {.inline.} =
  ## Returns `true` if the character is a space, tab, newline, or carriage return.
  return c in {' ', '\t', '\n', '\r'}

proc parseMarkdownContent(s: ScannerNode): Node =
  ## Parses markdown content until a condition is met
  # For now, just store the raw markdown content
  var start = s.currentIndex
  while not s.isAtEnd() and not s.isMdxTagStart():
    s.currentIndex += 1

  # Trim whitespace at the start and end
  var endIndex = s.currentIndex
  while start < s.currentIndex and s.source[start].isWhitespace():
    start += 1
  while endIndex > start and s.source[endIndex - 1].isWhitespace():
    endIndex -= 1
  result = Node(
    kind: MarkdownContent,
    range: Range(start: start, `end`: endIndex),
    children: @[]
  )

# ---------------- #
# MDX Components   #
# ---------------- #
type
  TokenKindMdxComponent = enum
    OpeningTagOpen # <
    OpeningTagClose # >
    OpeningTagSelfClosing # />
    ClosingTagOpen # </
    Identifier # Alphanumeric or underscore
    EqualSign # =
    StringLiteral # "..." or '...'
    # TODO: implement tokens below:
    # JSXExpression can contain nested literals and comma-separated values
    JSXExpression # {...}
    ArrayLiteral # []
    NumberLiteral # 123
    Comma # ,
    Comment # {/* ... */}

  TokenMdxComponent = object
    range: Range
    case kind: TokenKindMdxComponent
    of JSXExpression:
      children: seq[TokenMdxComponent]
    else:
      discard

proc tokenizeMdxTag(s: ScannerNode): tuple[range: Range, tokens: seq[TokenMdxComponent]] =
  ## Scans and tokenizes the contents of a single MDX tag into TokenKindMdxComponent tokens.
  ## This procedure assumes the scanner's current character is < and stops at
  ## the first encountered closing tag.
  ##
  ## It makes it easier to parse the component afterwards: we break down the
  ## component into identifiers, string literals, JSX expressions, etc.
  assert s.currentChar == '<', "The scanner should be at the start of an MDX tag for this procedure to work. Found " & s.currentChar & " instead."
  while not s.isAtEnd():
    s.skipWhitespace()
    let c = s.currentChar

    case c
    of '<':
      if s.peek(1) == '/':
        result.tokens.add(TokenMdxComponent(
          kind: ClosingTagOpen,
          range: Range(start: s.currentIndex, `end`: s.currentIndex + 2)
        ))
        s.currentIndex += 2
      else:
        result.tokens.add(TokenMdxComponent(
          kind: OpeningTagOpen,
          range: Range(start: s.currentIndex, `end`: s.currentIndex + 1)
        ))
        s.currentIndex += 1

    of '>':
      if s.peek(-1) == '/':
        result.tokens.add(TokenMdxComponent(
          kind: OpeningTagSelfClosing,
          range: Range(start: s.currentIndex - 1, `end`: s.currentIndex + 1)
        ))
      else:
        result.tokens.add(TokenMdxComponent(
          kind: OpeningTagClose,
          range: Range(start: s.currentIndex, `end`: s.currentIndex + 1)
        ))
      s.currentIndex += 1
      return

    of '=':
      result.tokens.add(TokenMdxComponent(
        kind: EqualSign,
        range: Range(start: s.currentIndex, `end`: s.currentIndex + 1)
      ))
      s.currentIndex += 1

    of '"', '\'':
      # String literal
      let quoteChar = c
      let start = s.currentIndex
      s.currentIndex += 1
      while not s.isAtEnd() and s.currentChar != quoteChar:
        s.currentIndex += 1
      if s.currentIndex >= s.source.len:
        raise ParseError(
          range: Range(start: start, `end`: s.currentIndex),
          message: "Found string literal opening character in an MDX tag but no closing character. " &
          "Expected " & quoteChar & " character to close the string literal."
        )
      s.currentIndex += 1
      result.tokens.add(TokenMdxComponent(
        kind: StringLiteral,
        range: Range(start: start, `end`: s.currentIndex)
      ))

    of '{':
      # JSX expression
      let start = s.currentIndex
      var depth = 1
      s.currentIndex += 1
      while not s.isAtEnd() and depth > 0:
        if s.currentChar == '{': depth += 1
        elif s.currentChar == '}': depth -= 1
        s.currentIndex += 1

      if depth != 0:
        raise ParseError(
          range: Range(start: start, `end`: s.currentIndex),
          message: "Found opening '{' character in an MDX tag but no matching closing character. " &
          "Expected a '}' character to close the JSX expression."
        )

      result.tokens.add(TokenMdxComponent(
        kind: JSXExpression,
        range: Range(start: start, `end`: s.currentIndex)
      ))
    else:
      # Identifier
      if isAlphanumericOrUnderscore(c):
        result.tokens.add(TokenMdxComponent(
          kind: Identifier,
          range: s.scanIdentifier()
        ))
      else:
        s.currentIndex += 1

proc parseMdxComponent(s: ScannerNode): Node =
  ## Parses an MDX component from the scanner's current position. Assumes that the scanner is at the start of an MDX component ('<' character).
  ##
  ## Rules to parse an MDX component:
  ##
  ## - The component name must start with an uppercase letter.
  ## - The component tag must be closed with a '>' character or '/>'. We scan until we find the closing tag.
  ## - The component tag can contain attributes. An attribute can be just an
  ## identifier (boolean value) or a key-value pair.
  ##
  ## This proc. parses the component and attributes but not JSX expressions ({...}).
  ## JSX expressions are stored as-is and not evaluated or validated here.
  let start = s.currentIndex

  let (tagRange, tokens) = s.tokenizeMdxTag()

  if tokens.len < 3:
    raise ParseError(
      range: tagRange,
      message: "Found a < character in the source document but no valid MDX component tag. " &
      "In MDX, a < marks the start of a component tag, which must contain an identifier and be closed with a > character or />.\n" &
      r"To write a literal < character in the document, escape it as '\<' or '&lt;'."
    )

  # First token must be opening < and second must be an identifier
  if tokens[0].kind != OpeningTagOpen or tokens[1].kind != Identifier:
    raise ParseError(
      range: tagRange,
      message: "Expected an opening < character followed by an identifier but found " &
      getString(tokens[0].range, s.source) & " and " & getString(tokens[1].range, s.source) & " instead."
    )

  # Component name must start with uppercase letter
  let nameToken = tokens[1]
  let firstChar = s.source[nameToken.range.start]
  if firstChar < 'A' or firstChar > 'Z':
    raise ParseError(
      range: nameToken.range,
      message: "Expected component name to start with an uppercase letter but found " & getString(nameToken.range, s.source) & " instead. A valid component name must start with an uppercase letter."
    )

  result.name = nameToken.range

  # Collect attributes
  var i = 2
  while i < tokens.len:
    if tokens[i].kind in {OpeningTagClose, OpeningTagSelfClosing}:
      break

    # Rules:
    #
    # - An attribute can be just an identifier (boolean value) or a key-value pair.
    # - A key-value pair is an identifier followed by an equal sign and a value
    # (JSX expression or string literal).
    if tokens[i].kind == Identifier:
      # If there are two identifiers in a row or a lone identifier at the end of the tag, it's a boolean attribute.
      if tokens[i + 1].kind in {Identifier, OpeningTagClose, OpeningTagSelfClosing}:
        result.attributes.add(MdxAttribute(
          range: tokens[i].range,
          name: tokens[i].range,
          value: AttributeValue(kind: AttributeKind.Boolean, boolValue: true)
        ))
      # Otherwise we look for the form 'identifier = value'
      # TODO: find a nicer way to express this like s.peekSequence([Identifier, EqualSign, Value])
      elif (
        i + 2 < tokens.len and tokens[i + 1].kind == EqualSign and
        tokens[i + 2].kind in {TokenKindMdxComponent.StringLiteral, TokenKindMdxComponent.JSXExpression}
      ):
        result.attributes.add(MdxAttribute(
          range: Range(start: tokens[i].range.start, `end`: tokens[i + 2].range.`end`),
          name: tokens[i].range,
          value: case tokens[i + 2].kind
            of TokenKindMdxComponent.StringLiteral:
              AttributeValue(kind: AttributeKind.StringLiteral, stringValue: tokens[i + 2].range)
            of TokenKindMdxComponent.JSXExpression:
              AttributeValue(kind: AttributeKind.JSXExpression, expressionRange: tokens[i + 2].range)
            else:
              raise ParseError(
                range: tokens[i + 2].range,
                message: "Expected string literal or JSX expression as attribute value"
              )
          ))
        i += 2 # Skip over the = and value tokens
      else:
        raise ParseError(
          range: tokens[i].range,
          message: "Expected attribute name to be followed by = and a value"
        )
    i += 1

  # Check if tag is self-closing by checking last token
  if tokens[^1].kind == OpeningTagSelfClosing:
    result.isSelfClosing = true

  if not result.isSelfClosing:
    let bodyStart = s.currentIndex
    echo "Parsing children. Current line: " & s.getCurrentLine()
    echo "Current char: " & s.currentChar.charMakeWhitespaceVisible()
    result.children = s.parseNodes()
    result.rangeBody = Range(start: bodyStart, `end`: s.currentIndex)

    let componentName = getString(result.name, s.source)
    while not s.isAtEnd():
      let closingTag = "</" & componentName & ">"
      if s.isPeekSequence(closingTag):
        s.currentIndex = s.peekIndex
        if not s.isAtEnd():
          s.currentIndex += 1
        break
      s.currentIndex += 1

  result.range = Range(start: start, `end`: s.currentIndex)

proc parseNodes(s: ScannerNode): seq[Node] =
  ## Parses a sequence of nodes from the scanner's current position.
  while not s.isAtEnd():
    if s.isMdxComponentStart():
      result.add(s.parseMdxComponent())
    elif s.isMdxClosingTagStart():
      break
    else:
      result.add(s.parseMarkdownContent())

# ---------------- #
#  Error handling  #
# ---------------- #
type
  Position* = object
    ## A position in a source document. Used for error reporting.
    line*, column*: int


proc findLineStartIndices*(source: string): seq[int] =
  ## Finds the start indices of each line in the source string. Run this on a
  ## document in case of errors or warnings. We don't track lines and columns
  ## for every token as they're only needed for error reporting.
  result = @[0]
  for i, c in source:
    if c == '\n':
      result.add(i + 1)

proc getLineAndColumn*(lineStartIndices: seq[int], index: int): Position =
  ## Finds the line and column number for the given character index
  var min = 0
  var max = lineStartIndices.len - 1

  while min <= max:
    let middle = (min + max).div(2)
    let lineStartIndex = lineStartIndices[middle]

    if index < lineStartIndex:
      max = middle - 1
    elif middle < lineStartIndices.len and index >= lineStartIndices[middle + 1]:
      min = middle + 1
    else:
      return Position(line: middle + 1, column: index - lineStartIndex + 1)


when isMainModule:
  import std/[strformat, unittest, strutils]

  proc echoTokens(source: string, tokens: seq[TokenMdxComponent]) =
    ## Prints tokens returned by tokenizeMdxTag in a readable format
    for token in tokens:
      let tokenText = source[token.range.start ..< token.range.`end`]
      echo fmt"{token.kind:<20} | '{tokenText}'"

  proc echoNodes(nodes: seq[Node], source: string, indent: int = 0) =
    ## Prints nodes in a readable format
    for node in nodes:
      case node.kind:
      of MdxComponent:
        let openingTag = source[node.range.start ..< node.rangeBody.start]
        echo ' '.repeat(indent) & fmt"{node.kind:<20} | {openingTag}"
        echoNodes(node.children, source, indent + 2)
      else:
        let nodeText = source[node.range.start ..< node.range.`end`]
        echo ' '.repeat(indent) & fmt"{node.kind:<20} | '{nodeText}'"

  test "tokenize MDX component with string and JSX expression attributes":
    let source = """<SomeComponent prop1="value1" prop2={value2}>
    Some text
</SomeComponent>"""

    var scanner = ScannerNode(
      source: source,
      currentIndex: 0
    )

    let (range, tokens) = tokenizeMdxTag(scanner)
    check:
      tokens.len == 9
      tokens[0].kind == OpeningTagOpen
      tokens[1].kind == Identifier # SomeComponent
      tokens[2].kind == Identifier # prop1
      tokens[3].kind == EqualSign
      tokens[4].kind == StringLiteral # "value1"
      tokens[5].kind == Identifier # prop2
      tokens[6].kind == EqualSign
      tokens[7].kind == JSXExpression # {value2}
      tokens[8].kind == OpeningTagClose

  test "parse self-closing mdx node":
    let source = "<SomeComponent prop1=\"value1\" prop2={value2} />"
    var scanner = ScannerNode(source: source, currentIndex: 0)
    let node = parseMdxComponent(scanner)

    echoNodes(@[node], source)

    check:
      node.kind == MdxComponent
      getString(node.name, source) == "SomeComponent"
      node.isSelfClosing

      node.attributes.len == 2
      getString(node.attributes[0].name, source) == "prop1"
      getString(node.attributes[0].value.stringValue, source) == "\"value1\""
      getString(node.attributes[1].name, source) == "prop2"
      getString(node.attributes[1].value.expressionRange, source) == "{value2}"


  test "parse nested components and markdown":
    let source = """
<OuterComponent>
  Some text with *markdown* formatting and an ![inline image](images/image.png).
  <InnerComponent prop="value">
    Nested **markdown** content.
  </InnerComponent>
  More text after the inner component.
</OuterComponent>"""

    var scanner = ScannerNode(source: source, currentIndex: 0)
    let nodes = parseNodes(scanner)

    echoNodes(nodes, source)

    check:
      nodes.len == 1
      nodes[0].kind == MdxComponent
      nodes[0].children.len > 0
      nodes[0].children[0].kind == MarkdownContent
      nodes[0].children[1].kind == MdxComponent
      nodes[0].children[1].children.len > 0
      nodes[0].children[1].children[0].kind == MarkdownContent
      nodes[0].children[2].kind == MarkdownContent
      nodes[0].children[2].range.getString(source) == "More text after the inner component."
