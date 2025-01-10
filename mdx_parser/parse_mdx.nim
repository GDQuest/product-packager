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
    name*: Range
    value*: AttributeValue

  NodeKind* = enum
    MdxComponent

  Node* = object
    case kind*: NodeKind
    of MdxComponent:
      name*: Range
      attributes*: seq[Range]
    range*: Range
      ## The start and end indices of the node in the source document.
      ## This can be used for error reporting.
    children*: seq[Node]

  ScannerNode* = ref object
    nodes*: seq[Node]
    currentIndex*: int
    source*: string
    peekIndex*: int

proc getString*(range: Range, source: string): string {.inline.} =
  return source[range.start ..< range.end]

proc currentChar*(s: ScannerNode): char {.inline.} =
  s.source[s.currentIndex]

proc peek*(s: ScannerNode, offset: int = 0): char {.inline.} =
  ## Returns the current character or a character at the desired offset in the
  ## source string, without advancing the scanner.
  ## Updates the peek index to the current position plus the offset. Call
  ## advanceToPeek() to move the scanner to the peek index.
  s.peekIndex = s.currentIndex + offset
  if s.peekIndex >= s.source.len:
    result = '\0'
  else:
    result = s.source[s.peekIndex]

proc advanceToPeek*(s: ScannerNode) {.inline.} =
  ## Advances the scanner to the peek index.
  s.currentIndex = s.peekIndex

proc isPeekSequence*(s: ScannerNode, sequence: string): bool {.inline.} =
  ## Returns `true` if the next chars in the scanner match the given sequence.
  for i, expectedChar in sequence:
    if s.peek(i) != expectedChar:
      return false
  return true

proc isAtEnd*(s: ScannerNode): bool {.inline.} =
  ## Returns `true` if the scanner has reached the end of the source string.
  s.currentIndex >= s.source.len

proc match*(s: ScannerNode, expected: char): bool {.inline.} =
  ## Advances the scanner and returns `true` if the current character matches
  ## the expected one.
  if s.currentIndex >= s.source.len or s.source[s.currentIndex] != expected:
    return false
  s.currentIndex += 1
  return true

proc isAlphanumericOrUnderscore*(c: char): bool {.inline.} =
  ## Returns `true` if the character is a letter (lower or uppercase), digit, or
  ## underscore.
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit

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
    range*: Range
    case kind*: TokenKindMdxComponent
    of JSXExpression:
      children*: seq[TokenMdxComponent]
    else:
      discard

proc skipWhitespace*(s: ScannerNode) {.inline.} =
  ## Advances the scanner until it finds a non-whitespace character.
  ## Skips spaces, tabs, newlines, and carriage returns.
  while not s.isAtEnd() and s.currentChar in {' ', '\t', '\n', '\r'}:
    s.currentIndex += 1


proc scanIdentifier*(s: ScannerNode): Range =
  ## Scans and returns the range of an identifier in the source string,
  ## advancing the scanner to the end of the identifier.
  let start = s.currentIndex
  while not s.isAtEnd() and isAlphanumericOrUnderscore(s.currentChar):
    s.currentIndex += 1
  result = Range(start: start, `end`: s.currentIndex)

proc tokenizeMdxTag*(s: ScannerNode): tuple[range: Range, tokens: seq[TokenMdxComponent]] =
  ## Scans and tokenizes the content of an MDX tag into TokenKindMdxComponent tokens.
  ## This procedure assumes the scanner's current character is < and stops at
  ## the first encountered closing tag.
  ##
  ## It makes it easier to parse the component afterwards: we break down the
  ## component into identifiers, string literals, JSX expressions, etc.
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
      result.add(TokenMdxComponent(
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
      result.add(TokenMdxComponent(
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

      result.add(TokenMdxComponent(
        kind: JSXExpression,
        range: Range(start: start, `end`: s.currentIndex)
      ))
    else:
      # Identifier
      if isAlphanumericOrUnderscore(c):
        result.add(TokenMdxComponent(
          kind: Identifier,
          range: s.scanIdentifier()
        ))
      else:
        s.currentIndex += 1

proc parseMdxComponent*(s: ScannerNode): Node =
  var node = Node(kind: MdxComponent)
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

  node.name = nameToken.range

  # Collect attributes
  var i = 2
  while i < tokens.len:
    if tokens[i].kind == OpeningTagClose:
      break

    # Add attribute ranges
    if tokens[i].kind in {StringLiteral, JSXExpression}:
      node.attributes.add(tokens[i].range)

    i += 1

  let tagEnd = tagRange.`end`
  var isSelfClosing = false

  # Check if tag is self-closing by looking at last two chars
  if s.source[tagEnd-2 ..< tagEnd] == "/>":
    isSelfClosing = true

  # If not self-closing, look for matching closing tag
  if not isSelfClosing:
    let componentName = s.source[node.name.start ..< node.name.`end`]
    while not s.isAtEnd():
      if s.isPeekSequence("</" & componentName & ">"):
        s.currentIndex = s.peekIndex + ("</" & componentName & ">").len
        break
      s.currentIndex += 1

      node.range = Range(start: start, `end`: s.currentIndex)
  result = node

type
  StateKind = enum
    Normal
    InCodeFence
    InMdxTag

  State* = object
    kind*: StateKind
    startIndex*: int

  Context = object
    stateStack*: seq[State]
    stateCurrent*: proc (): State

proc stateCurrent*(c: Context): State {.inline.} =
  assert(c.stateStack.len > 0, "State stack is empty, it should always contain at least one state")
  result = c.stateStack[c.stateStack.len - 1]

proc parseMdxDocument*(s: ScannerNode): seq[Node] =
  # We keep a stateStack of states to handle nested elements: MDX components could
  # contain markdown which could contain MDX components.
  # TODO: Question: Should we track more context like start indices of each element?
  #
  var context = Context(stateStack: @[State(kind: StateKind.Normal, startIndex: 0)])

  while not s.isAtEnd():
    let c = s.source[s.currentIndex]
    case c
    of '<':
      stateStack.add(State.InMdxTag)
      let node = parseMdxComponent(s)
      result.add(node)
    else:
      discard
    s.currentIndex += 1

# ---------------- #
#  Error handling  #
# ---------------- #
type
  Position* = object
    ## A position in a source document. Used for error reporting.
    line*, column*: int

  ParseError* = ref object of ValueError
    range*: Range
      message*: string

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
