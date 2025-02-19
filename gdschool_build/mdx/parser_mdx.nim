import std/strformat

## Parses MDX files and produces a tree of nodes.
type
  ParseError = ref object of ValueError
    range: Range

  Range = object
    ## A range of character indices in a source string or in a sequence of nodes.
    start, `end`: int

  AttributeKind = enum
    akBoolean
    akNumber
    akString
    akJSXExpression

  Attribute = object
    name: Range
    range: Range
    case kind: AttributeKind
    of akBoolean:
      boolValue: bool
    else:
      value: Range

  NodeKind = enum
    nkMDXComponent
    # Temporary: we'll add more node types later
    nkMarkdownContent

  Node = object
    case kind: NodeKind
    of nkMDXComponent:
      name: Range
      attributes: seq[Attribute]
      isSelfClosing: bool
      rangeOpeningTag: Range
      rangeBody: Range
      rangeClosingTag: Range
    else:
      discard
    range: Range
      ## The start and end indices of the node in the source document.
      ## This can be used for error reporting.
    children: seq[Node]

  Scanner = object
    source: string
    index: int
    peekIndex: int
    nodes: seq[Node]

func currentChar(s: Scanner): char {.inline.} = s.source[s.index]

func getChar(s: Scanner, at: int): char {.inline.} = s.source[at]

func getString(s: Scanner, range: Range): string {.inline.} = s.source[range.start ..< range.end]

func isAtEnd(s: Scanner): bool {.inline.} = s.index >= s.source.len
  ## Returns `true` if the scanner has reached the end of the source string.

func isWhitespace(c: char): bool {.inline.} = c in " \t\n\r"
  ## Returns `true` if the character is a space, tab, newline, or carriage return.

func isUppercaseAscii(c: char): bool {.inline.} = c >= 'A' and c <= 'Z'

func isDigit(c: char): bool {.inline.} = c >= '0' and c <= '9'

func isAlphanumericOrUnderscore(c: char): bool {.inline.} =
  ## Returns `true` if the character is a letter (lower or uppercase), digit, or underscore.
  let isLetter = c == '_' or (c >= 'a' and c <= 'z') or c.isUppercaseAscii()
  return isLetter or c.isDigit()

proc advance(s: var Scanner, offset: int = 1): int {.inline.} =
  ## Advances the scanner index by the given offset.
  s.index += offset
  return s.index

proc peek(s: var Scanner, offset: int = 1): char {.inline.} =
  ## Returns the current character or a character at the desired offset in the
  ## source string, without advancing the scanner.
  ##
  ## Updates the peek index to the current position plus the offset. Call
  ## advanceToPeek() to move the scanner to the peek index.
  s.peekIndex = s.index + offset
  return if s.peekIndex >= s.source.len: '\0' else: s.source[s.peekIndex]

proc advanceToPeek(s: var Scanner): int {.inline.} = 
  ## Advances the scanner to the peek index.
  s.index = s.peekIndex
  return s.index

proc skipWhitespace(s: var Scanner) {.inline.} =
  ## Advances the scanner until it finds a non-whitespace character.
  ## Skips spaces, tabs, newlines, and carriage returns.
  while not s.isAtEnd() and s.currentChar.isWhitespace():
    discard s.advance()

proc matchString(s: var Scanner, expected: string): bool {.inline.} =
  ## Returns `true` if the next chars in the scanner match the expected string.
  result = s.source[s.index ..< (s.index + expected.len)] == expected
  if result:
    s.index += expected.len

proc matchChar(s: var Scanner, expected: char): bool {.inline.} =
  ## Advances the scanner and returns `true` if the current character matches the expected char
  ## or if we're at end of the source string.
  result = s.index >= s.source.len or s.source[s.index] != expected
  if result:
    discard s.advance()

proc scanIdentifier(s: var Scanner): Range =
  ## Scans and returns the range of an identifier in the source string,
  ## advancing the scanner to the end of the identifier.
  let start = s.index
  while not s.isAtEnd() and s.currentChar.isAlphanumericOrUnderscore():
    discard s.advance()
  return Range(start: start, `end`: s.index)

func isMDXComponentStart(s: var Scanner): bool {.inline.} = s.currentChar == '<' and s.peek().isUppercaseAscii()
  ## Returns `true` if the scanner is at the start of an MDX component.

proc isMDXClosingTagStart(s: var Scanner): bool {.inline.} = s.currentChar == '<' and s.peek() == '/'
  ## Returns `true` if the scanner is at the start of an MDX component closing tag.

proc isMDXTagStart(s: var Scanner): bool {.inline.} = s.currentChar == '<' and (s.peek().isUppercaseAscii() or s.peek() == '/')
  ## Returns `true` if the scanner is at the start of an MDX component closing tag.

# ---------------- #
#  Error handling  #
# ---------------- #
type
  Position = object
    ## A position in a source document. Used for error reporting.
    line, column: int

func getLineStartIndices(s: Scanner): seq[int] =
  ## Finds the start indices of each line in the source string. Run this on a
  ## document in case of errors or warnings. We don't track lines and columns
  ## for every token as they're only needed for error reporting.
  result = @[0]
  for i, c in s.source:
    if c == '\n':
      result.add(i + 1)

func position(s: Scanner): Position =
  let lineStartIndices = s.getLineStartIndices()
  ## Finds the line and column number for the given character index
  var min = 0
  var max = lineStartIndices.len - 1
  while min <= max:
    let middle = (min + max).div(2)
    let lineStartIndex = lineStartIndices[middle]

    if s.index < lineStartIndex:
      max = middle - 1
    elif middle < lineStartIndices.len and s.index >= lineStartIndices[middle + 1]:
      min = middle + 1
    else:
      return Position(line: middle + 1, column: s.index - lineStartIndex + 1)

func currentLine(s: Scanner): string =
  ## Returns the current line of the scanner without advancing the scanner's current index.
  ## Use this for debugging purposes.
  let lineStartIndices = s.getLineStartIndices()
  var lineRange = Range()
  for lineStartIndex in lineStartIndices:
    lineRange.start = lineStartIndex
    if s.index >= lineRange.start:
      break

  while s.getChar(lineRange.end) != '\n' and not s.isAtEnd():
    lineRange.end += 1
  return s.getString(lineRange)

# ---------------- #
#     Markdown     #
# ---------------- #
proc parseMarkdownContent(s: var Scanner): Node =
  ## Parses markdown content until a condition is met
  # For now, just store the raw markdown content
  var start = s.index
  while not s.isAtEnd() and not s.isMDXTagStart():
    discard s.advance()

  # Trim whitespace at the start and end
  var endIndex = s.index
  while start < s.index and s.getChar(start).isWhitespace():
    start += 1

  while endIndex > start and s.getChar(endIndex - 1).isWhitespace():
    endIndex -= 1

  return Node(
    kind: nkMarkdownContent,
    range: Range(start: start, `end`: endIndex),
  )

# ---------------- #
# MDX Components   #
# ---------------- #
type
  TokenMDXComponentKind = enum
    tmcOpeningTagOpen # <
    tmcOpeningTagClose # >
    tmcOpeningTagSelfClosing # />
    tmcClosingTagOpen # </
    tmcIdentifier # Alphanumeric or underscore
    tmcEqualSign # =
    tmcString # "..." or '...'
    tmcNumber, # 123 or 123.45
    tmcColon, # :
    tmcComma, # ,
    tmcJSXExpression, # {...}
    # tmcJSXComment, # {/* ... */}

    # jsx -> "{" values? "}";
    # array -> "[" values? "]";
    # object -> "{" objectValues? "}";
    # objectValues -> ( STRING ":" values ) ( "," ( STRING ":" values ) )*;
    # values -> value ( "," value )*
    # value -> ( NUMBER | STRING | array | object )
    tmcJSXOpen, # {
    tmcJSXClose, # }
    tmcJSXOpenArray, # [
    tmcJSXCloseArray, # ]
    tmcJSXOpenObject, # {
    tmcJSXCloseObject, # }

  TokenMDXComponent = object
    range: Range
    case kind: TokenMDXComponentKind
    of tmcJSXExpression:
      children: seq[TokenMDXComponent]
    else:
      discard

proc tokenizeJSX(s: var Scanner): tuple[range: Range, tokens: seq[TokenMDXComponent]] =
  assert s.currentChar in "[{", fmt"The scanner should be at the start of a JSX expression for this procedure to work. Found {s.currentChar} instead."

  result.range.start = s.index
  var depth = 0

  while not s.isAtEnd() and depth >= 0:
    s.skipWhitespace()
    case s.currentChar
    of '{':
      depth += 1
      result.tokens.add(TokenMDXComponent(
        range: Range(start: s.index, `end`: s.advance()),
        kind: if depth == 1: tmcJSXOpen else: tmcJSXOpenObject
      ))
    of '}':
      depth -= 1
      result.tokens.add(TokenMDXComponent(
        range: Range(start: s.index, `end`: s.advance()),
        kind: if depth == 0: tmcJSXClose else: tmcJSXCloseObject
      ))
    of '[':
      result.tokens.add(TokenMDXComponent(
        range: Range(start: s.index, `end`: s.advance()),
        kind: tmcJSXOpenArray
      ))
    of ']':
      result.tokens.add(TokenMDXComponent(
        range: Range(start: s.index, `end`: s.advance()),
        kind: tmcJSXCloseArray
      ))
    of '"', '\'':
      let start = s.index
      let quoteChar = s.currentChar
      while not (s.peek() in "\"'" or s.isAtEnd()):
        discard s.advance()

      if s.isAtEnd():
        raise ParseError(
          range: Range(start: start, `end`: s.index),
          msg: "Found string literal opening character in an JSX tag but no closing character. " &
            fmt"Expected `{quoteChar}` character to close the string literal."
        )

      discard s.advance(2)
      result.tokens.add(TokenMDXComponent(
        range: Range(start: start, `end`: s.index),
        kind: tmcString
      ))
    of ':':
      result.tokens.add(TokenMDXComponent(
        range: Range(start: s.index, `end`: s.advance()),
        kind: tmcColon
      ))
    of ',':
      result.tokens.add(TokenMDXComponent(
        range: Range(start: s.index, `end`: s.advance()),
        kind: tmcComma
      ))
    elif s.currentChar.isDigit():
      let start = s.index
      while s.currentChar.isDigit():
        discard s.advance()

      if s.currentChar == '.' and s.peek().isDigit():
        discard s.advance()

      while s.currentChar.isDigit():
        discard s.advance()

      result.tokens.add(TokenMDXComponent(
        range: Range(start: start, `end`: s.index),
        kind: tmcNumber
      ))
    elif depth == 0:
      break
    else:
      let range = Range(start: s.index, `end`: s.source.len)
      raise ParseError(
        range: range,
        msg: fmt"Found invalid JSX expression at `{s.index}`: `{s.getString(range)}`"
      )

  if s.isAtEnd() and depth != 0:
    raise ParseError(
      range: Range(start: result.range.start, `end`: s.index),
      msg: "Found `{` JSX expression opening character, but no closing character. Expected `}` character to close the JSX expression."
    )
  result.range.end = s.index


proc tokenizeMDXComponent(s: var Scanner): tuple[range: Range, tokens: seq[TokenMdxComponent]] =
  ## Scans and tokenizes the contents of a single MDX tag into TokenKindMdxComponent tokens.
  ## This procedure assumes the scanner's current character is < and stops at
  ## the first encountered closing tag.
  ##
  ## It makes it easier to parse the component afterwards: we break down the
  ## component into identifiers, string literals, JSX expressions, etc.
  assert s.currentChar == '<', "The scanner should be at the start of an MDX tag for this procedure to work. Found " & s.currentChar & " instead."

  result.range.start = s.index
  while not s.isAtEnd():
    s.skipWhitespace()
    let c = s.currentChar
    case c
    of '<':
      if s.peek() == '/':
        result.tokens.add(TokenMdxComponent(
          kind: tmcClosingTagOpen,
          range: Range(start: s.index, `end`: s.advance(2))
        ))
      else:
        result.tokens.add(TokenMdxComponent(
          kind: tmcOpeningTagOpen,
          range: Range(start: s.index, `end`: s.advance())
        ))

    of '>':
      if s.peek(-1) == '/':
        result.tokens.add(TokenMdxComponent(
          kind: tmcOpeningTagSelfClosing,
          range: Range(start: s.index - 1, `end`: s.advance())
        ))
      else:
        result.tokens.add(TokenMdxComponent(
          kind: tmcOpeningTagClose,
          range: Range(start: s.index, `end`: s.advance())
        ))
      result.range.end = s.index
      return

    of '=':
      result.tokens.add(TokenMdxComponent(
        kind: tmcEqualSign,
        range: Range(start: s.index, `end`: s.advance())
      ))

    of '"', '\'':
      # String literal
      let quoteChar = c
      let start = s.index
      discard s.advance()
      while not s.isAtEnd() and s.currentChar != quoteChar:
        discard s.advance()
      if s.index >= s.source.len:
        raise ParseError(
          range: Range(start: start, `end`: s.index),
          msg: "Found string literal opening character in an MDX tag but no closing character. " &
            fmt"Expected `{quoteChar}` character to close the string literal."
        )
      result.tokens.add(TokenMdxComponent(
        kind: tmcString,
        range: Range(start: start, `end`: s.advance())
      ))

    of '{':
      # JSX expression
      let start = s.index
      var depth = 1
      discard s.advance()
      while not s.isAtEnd() and depth > 0:
        if s.currentChar == '{': depth += 1
        elif s.currentChar == '}': depth -= 1
        discard s.advance()

      if depth != 0:
        raise ParseError(
          range: Range(start: start, `end`: s.index),
          msg: "Found opening `{` character in an MDX tag but no matching closing character. " &
            "Expected a `}` character to close the JSX expression."
        )

      result.tokens.add(TokenMdxComponent(
        kind: tmcJSXExpression,
        range: Range(start: start, `end`: s.index)
      ))
    else:
      # Identifier
      if isAlphanumericOrUnderscore(c):
        result.tokens.add(TokenMdxComponent( kind: tmcIdentifier, range: s.scanIdentifier()))
      else:
        discard s.advance()
    result.range.end = s.index

# Forward declaractions to avoid errors with cyclical calls
proc parseNodes(s: var Scanner): seq[Node]
proc parseComponent(s: var Scanner): Node

proc parseNodes(s: var Scanner): seq[Node] =
  ## Parses a sequence of nodes from the scanner's current position.
  while not s.isAtEnd():
    if s.isMDXComponentStart():
      result.add(s.parseComponent())
    elif s.isMDXClosingTagStart():
      break
    else:
      result.add(s.parseMarkdownContent())

proc parseComponent(s: var Scanner): Node =
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
  let start = s.index
  let (tagRange, tokens) = s.tokenizeMDXComponent()
  if tokens.len < 3:
    raise ParseError(
      range: tagRange,
      msg: "Found a `<` character in the source document but no valid MDX component tag. " &
        "In MDX, `<` marks the start of a component tag, which must contain an identifier and " &
        "be closed with a `>` character or `/>`.\nTo write a literal `<` character in the " &
        r"document, escape it as `\<` or `&lt;`."
    )

  # First token must be opening < and second must be an identifier
  if tokens[0].kind != tmcOpeningTagOpen or tokens[1].kind != tmcIdentifier:
    raise ParseError(
      range: tagRange,
      msg: "Expected an opening `<` character followed by an identifier, but found " &
        fmt"`{s.getString(tokens[0].range)}` and `{s.getString(tokens[1].range)}` instead."
    )

  # Component name must start with uppercase letter
  let nameToken = tokens[1]
  let firstChar = s.source[nameToken.range.start]
  if firstChar < 'A' or firstChar > 'Z':
    raise ParseError(
      range: nameToken.range,
      msg: "Expected component name to start with an uppercase letter but found " &
        fmt"{s.getString(nameToken.range)} instead. A valid component name must start with " &
        "an uppercase letter."
    )
  result.name = nameToken.range

  # Collect attributes
  var i = 2
  while i < tokens.len:
    if tokens[i].kind in {tmcOpeningTagClose, tmcOpeningTagSelfClosing}:
      break

    # Rules:
    #
    # - An attribute can be just an identifier (boolean value) or a key-value pair.
    # - A key-value pair is an identifier followed by an equal sign and a value
    # (JSX expression or string literal).
    if tokens[i].kind == tmcIdentifier:
      # If there are two identifiers in a row or a lone identifier at the end of the tag, it's a boolean attribute.
      if tokens[i + 1].kind in {tmcIdentifier, tmcOpeningTagClose, tmcOpeningTagSelfClosing}:
        result.attributes.add(Attribute(
          kind: akBoolean,
          range: tokens[i].range,
          name: tokens[i].range,
          boolValue: true,
        ))
      # Otherwise we look for the form 'identifier = value'
      # TODO: find a nicer way to express this like s.peekSequence([Identifier, EqualSign, Value])
      elif (
        i + 2 < tokens.len and tokens[i + 1].kind == tmcEqualSign and
        tokens[i + 2].kind in {tmcString, tmcJSXExpression}
      ):
        case tokens[i + 2].kind
        of tmcString:
          result.attributes.add(Attribute(
            kind: akString,
            range: Range(start: tokens[i].range.start, `end`: tokens[i + 2].range.end),
            name: tokens[i].range,
            value: tokens[i + 2].range
          ))
        of tmcJSXExpression: 
          result.attributes.add(Attribute(
            kind: akJSXExpression,
            range: Range(start: tokens[i].range.start, `end`: tokens[i + 2].range.end),
            name: tokens[i].range,
            value: tokens[i + 2].range
          ))
        else:
          raise ParseError(
            range: tokens[i + 2].range,
            msg: "Expected `string` or JSX expression as `attribute value`"
          )
        i += 2 # Skip over the = and value tokens
      else:
        raise ParseError(
          range: tokens[i].range,
          msg: "Expected `attribute name` to be followed by `=` and a `value`"
        )
    i += 1

  # Check if tag is self-closing by checking last token
  if tokens[^1].kind == tmcOpeningTagSelfClosing:
    result.isSelfClosing = true

  if not result.isSelfClosing:
    let bodyStart = s.index
    result.children = s.parseNodes()
    result.rangeBody = Range(start: bodyStart, `end`: s.index)

    let componentName = s.getString(result.name)
    while not s.isAtEnd():
      let closingTag = "</" & componentName & ">"
      if s.matchString(closingTag):
        break

  result.range = Range(start: start, `end`: s.index)

# ----------------- #
#  Automated tests  #
# ----------------- #
when isMainModule:
  import std/[strutils, unittest]

  proc echoTokens(s: Scanner, tokens: seq[TokenMdxComponent]) =
    ## Prints tokens returned by tokenizeMDXComponent in a readable format
    for token in tokens:
      echo fmt"{token.kind:<20} | `{s.getString(token.range)}`"

  proc echoNodes(s: Scanner, nodes: seq[Node], indent: int = 0) =
    ## Prints nodes in a readable format
    for node in nodes:
      case node.kind:
      of nkMDXComponent:
        echo ' '.repeat(indent) & fmt"{node.kind:<20} | `{s.getString(node.rangeOpeningTag)}`"
        echoNodes(s, node.children, indent + 2)
      else:
        echo ' '.repeat(indent) & fmt"{node.kind:<20} | `{s.getString(node.range)}`"

  test "tokenize MDX component with string and JSX expression attributes":
    let source = """<SomeComponent prop1="value1" prop2={value2}>
    Some text
</SomeComponent>"""

    var scanner = Scanner( source: source, index: 0)
    let (range, tokens) = scanner.tokenizeMDXComponent()
    check:
      tokens.len == 9
      tokens[0].kind == tmcOpeningTagOpen
      tokens[1].kind == tmcIdentifier # SomeComponent
      tokens[2].kind == tmcIdentifier # prop1
      tokens[3].kind == tmcEqualSign
      tokens[4].kind == tmcString # "value1"
      tokens[5].kind == tmcIdentifier # prop2
      tokens[6].kind == tmcEqualSign
      tokens[7].kind == tmcJSXExpression # {value2}
      tokens[8].kind == tmcOpeningTagClose

  test "parse self-closing mdx node":
    let source = "<SomeComponent prop1=\"value1\" prop2={value2} />"
    var scanner = Scanner(source: source, index: 0)
    let node = parseComponent(scanner)
    scanner.echoNodes(@[node])

    check:
      node.kind == nkMDXComponent
      scanner.getString(node.name) == "SomeComponent"
      node.isSelfClosing

      node.attributes.len == 2
      scanner.getString(node.attributes[0].name) == "prop1"
      scanner.getString(node.attributes[0].value) == "\"value1\""
      scanner.getString(node.attributes[1].name) == "prop2"
      scanner.getString(node.attributes[1].value) == "{value2}"


  test "parse nested components and markdown":
    let source = """
<OuterComponent>
  Some text with *markdown* formatting and an ![inline image](images/image.png).
  <InnerComponent prop="value">
    Nested **markdown** content.
  </InnerComponent>
  More text after the inner component.
</OuterComponent>"""

    var scanner = Scanner(source: source, index: 0)
    let nodes = parseNodes(scanner)

    echo "\nTest: parse nested components and markdown\n"
    scanner.echoNodes(nodes)

    check:
      nodes.len == 1
      nodes[0].kind == nkMDXComponent
      scanner.getString(nodes[0].name) == "OuterComponent"
      nodes[0].attributes.len == 0
      nodes[0].children.len > 0
      nodes[0].children[0].kind == nkMarkdownContent
      nodes[0].children[1].kind == nkMDXComponent
      scanner.getString(nodes[0].children[1].name) == "InnerComponent"
      nodes[0].children[1].attributes.len == 1
      scanner.getString(nodes[0].children[1].attributes[0].name) == "prop"
      nodes[0].children[1].attributes[0].kind == akString
      scanner.getString(nodes[0].children[1].attributes[0].value) == "\"value\""
      nodes[0].children[1].children.len > 0
      nodes[0].children[1].children[0].kind == nkMarkdownContent
      nodes[0].children[2].kind == nkMarkdownContent
      scanner.getString(nodes[0].children[2].range) == "More text after the inner component."

  test "tokenize JSX expression":
    let source = """{{123.4: "str", "some": ["other", 2]}, [2], [3, "a"]}"""
    var scanner = Scanner(source: source)
    let (range, tokens) = scanner.tokenizeJSX()

    check:
      range == Range(start: 0, `end`: source.len)
      tokens.len == 25
      tokens[0].kind == tmcJSXOpen
      tokens[1].kind == tmcJSXOpenObject
      tokens[2].kind == tmcNumber
      scanner.getString(tokens[2].range) == "123.4"
      tokens[3].kind == tmcColon
      tokens[4].kind == tmcString
      scanner.getString(tokens[4].range) == "\"str\""
      tokens[5].kind == tmcComma
      tokens[6].kind == tmcString
      scanner.getString(tokens[6].range) == "\"some\""
      tokens[7].kind == tmcColon
      tokens[8].kind == tmcJSXOpenArray
      tokens[9].kind == tmcString
      scanner.getString(tokens[9].range) == "\"other\""
      tokens[10].kind == tmcComma
      tokens[11].kind == tmcNumber
      scanner.getString(tokens[11].range) == "2"
      tokens[12].kind == tmcJSXCloseArray
      tokens[13].kind == tmcJSXCloseObject
      tokens[14].kind == tmcComma
      tokens[15].kind == tmcJSXOpenArray
      tokens[16].kind == tmcNumber
      scanner.getString(tokens[11].range) == "2"
      tokens[17].kind == tmcJSXCloseArray
      tokens[18].kind == tmcComma
      tokens[19].kind == tmcJSXOpenArray
      tokens[20].kind == tmcNumber
      scanner.getString(tokens[20].range) == "3"
      tokens[21].kind == tmcComma
      tokens[22].kind == tmcString
      scanner.getString(tokens[22].range) == "\"a\""
      tokens[23].kind == tmcJSXCloseArray
      tokens[24].kind == tmcJSXClose

