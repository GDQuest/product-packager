## Parses MDX components contained in MDX files into a tree of nodes.
type
  Range* = object
    ## A range of character indices in a source string or in a sequence of
    ## nodes.
    start*: int
    `end`*: int

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
    current*: int
    source*: string
    peekIndex*: int

proc getString*(range: Range, source: string): string {.inline.} =
  return source[range.start ..< range.end]

proc current*(s: ScannerNode): char {.inline.} =
  s.source[s.current]

proc peek*(s: ScannerNode, offset: int = 0): char {.inline.} =
  ## Returns the current character or a character at the desired offset in the
  ## source string, without advancing the scanner.
  ## Updates the peek index to the current position plus the offset. Call
  ## advanceToPeek() to move the scanner to the peek index.
  s.peekIndex = s.current + offset
  if s.peekIndex >= s.source.len:
    result = '\0'
  else:
    result = s.source[s.peekIndex]

proc advanceToPeek*(s: ScannerNode) {.inline.} =
  ## Advances the scanner to the peek index.
  s.current = s.peekIndex

proc isPeekSequence*(s: ScannerNode, sequence: string): bool {.inline.} =
  ## Returns `true` if the next chars in the scanner match the given sequence.
  for i, expectedChar in sequence:
    if s.peek(i) != expectedChar:
      return false
  return true

proc isAtEnd*(s: ScannerNode): bool {.inline.} =
  ## Returns `true` if the scanner has reached the end of the source string.
  s.current >= s.source.len

proc match*(s: ScannerNode, expected: char): bool {.inline.} =
  ## Advances the scanner and returns `true` if the current character matches
  ## the expected one.
  if s.current >= s.source.len or s.source[s.current] != expected:
    return false
  s.current += 1
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
    TagOpen
    TagClose
    Identifier
    EqualSign
    StringLiteral
    JSXExpression

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
  while not s.isAtEnd():
    let c = s.current
    if c notin {' ', '\t', '\n', '\r'}:
      break
    s.current += 1

proc scanIdentifier*(s: ScannerNode): Range =
  ## Scans and returns the range of an identifier in the source string,
  ## advancing the scanner to the end of the identifier.
  let start = s.current
  while not s.isAtEnd():
    let c = s.current
    if not isAlphanumericOrUnderscore(c):
      break
    s.current += 1
  result = Range(start: start, `end`: s.current)

proc tokenizeMdxExpression*(s: ScannerNode): seq[TokenMdxComponent] =
  ## Tokenizes the content of an MDX component into TokenKindMdxComponent tokens.
  ## It's to make it easier to parse the component afterwards: we break down the
  ## component into identifiers, string literals, JSX expressions, etc.
  while not s.isAtEnd():
    s.skipWhitespace()
    let c = s.current

    case c
    of '<':
      result.add(TokenMdxComponent(
        kind: TagOpen,
        range: Range(start: s.current, `end`: s.current + 1)
      ))
      s.current += 1

    of '>':
      result.add(TokenMdxComponent(
        kind: TagClose,
        range: Range(start: s.current, `end`: s.current + 1)
      ))
      s.current += 1
      return

    of '=':
      result.add(TokenMdxComponent(
        kind: EqualSign,
        range: Range(start: s.current, `end`: s.current + 1)
      ))
      s.current += 1

    of '"', '\'':
      # String literal
      let quoteChar = c
      let start = s.current
      s.current += 1
      while not s.isAtEnd() and s.current != quoteChar:
        s.current += 1
      if s.current >= s.source.len:
        raise ParseError(
          range: Range(start: start, `end`: s.current),
          message: "Unterminated string literal"
        )
      s.current += 1
      result.add(TokenMdxComponent(
        kind: StringLiteral,
        range: Range(start: start, `end`: s.current)
      ))

    of '{':
      # JSX expression
      let start = s.current
      var depth = 1
      s.current += 1
      while not s.isAtEnd() and depth > 0:
        if s.current == '{': depth += 1
        elif s.current == '}': depth -= 1
        s.current += 1

      if depth != 0:
        raise ParseError(
          range: Range(start: start, `end`: s.current),
          message: "Unterminated JSX expression"
        )

      result.add(TokenMdxComponent(
        kind: JSXExpression,
        range: Range(start: start, `end`: s.current)
      ))

    else:
      # Identifier
      if isAlphanumericOrUnderscore(c):
        result.add(TokenMdxComponent(
          kind: Identifier,
          range: s.scanIdentifier()
        ))
      else:
        s.current += 1

proc parseMdxComponent*(s: ScannerNode): Node =
  var node = Node(kind: MdxComponent)
  let start = s.current

  # Get component name. It has to start with an uppercase letter.
  var nameRange: Range
  let firstChar = s.source[start]
  if firstChar >= 'A' and firstChar <= 'Z':
    # Find end of component name (first non-alphanumeric/underscore character)
    var nameEnd = start + 1
    while nameEnd < s.source.len:
      let c = s.source[nameEnd]
      if not isAlphanumericOrUnderscore(c):
        break
      nameEnd += 1
    nameRange = Range(start: start, `end`: nameEnd)
    s.current += 1
  else:
    return node

  # Look for end of opening tag or self-closing mark
  var wasClosingMarkFound = false
  var isSelfClosing = false
  while not s.isAtEnd():
    let c = s.source[s.current]
    case c
    of '/':
      if s.source[s.current + 1] == '>':
        isSelfClosing = true
        wasClosingMarkFound = true
        s.current += 2
        break
      else:
        s.current += 1
    of '>':
      wasClosingMarkFound = true
      s.current += 1
      break
    else:
      s.current += 1

  if not wasClosingMarkFound:
    raise ParseError(
      range: Range(start: start, `end`: s.current),
      message: "Expected closing mark '>' or self-closing mark '/>'",
    )

  let openingTagEnd = s.current
  var bodyEnd = openingTagEnd

  # If the component is not self-closing, then we have to look for a matching
  # closing tag with the form </ComponentName>
  if not isSelfClosing:
    let componentName = s.source[nameRange.start ..< nameRange.end]
    while not s.isAtEnd():
      let c = s.source[s.current]
      if c == '<' and s.source[s.current + 1] == '/':
        bodyEnd = s.current
        s.current += 2

        # Check for matching component name
        let nameStart = s.current
        var nameEnd = nameStart
        while nameEnd < s.source.len:
          let c = s.source[nameEnd]
          if not isAlphanumericOrUnderscore(c):
            break
          nameEnd += 1

        if s.source[nameStart ..< nameEnd] == componentName:
          s.current = nameEnd
          if s.source[s.current] == '>':
            s.current += 1
            break
        break
      s.current += 1

  node.name = nameRange
  node.range = Range(start: start, `end`: s.current)
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
    let c = s.source[s.current]
    case c
    of '<':
      stateStack.add(State.InMdxTag)
      let node = parseMdxComponent(s)
      result.add(node)
    else:
      discard
    s.current += 1

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
