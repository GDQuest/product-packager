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

  Scanner* = ref object
    nodes*: seq[Node]
    current*: int
    source*: string
    peekIndex*: int

proc getString*(range: Range, source: string): string {.inline.} =
  return source[range.start ..< range.end]

proc current*(s: Scanner): char {.inline.} =
  s.source[s.current]

proc peek*(s: Scanner, offset: int = 0): char {.inline.} =
  ## Returns the current character or a character at the desired offset in the
  ## source string, without advancing the scanner.
  ## Updates the peek index to the current position plus the offset. Call
  ## advanceToPeek() to move the scanner to the peek index.
  s.peekIndex = s.current + offset
  if s.peekIndex >= s.source.len:
    result = '\0'
  else:
    result = s.source[s.peekIndex]

proc advanceToPeek*(s: Scanner) {.inline.} =
  ## Advances the scanner to the peek index.
  s.current = s.peekIndex

proc isPeekSequence*(s: Scanner, sequence: string): bool {.inline.} =
  ## Returns `true` if the next chars in the scanner match the given sequence.
  for i, expectedChar in sequence:
    if s.peek(i) != expectedChar:
      return false
  return true

proc isAtEnd*(s: Scanner): bool {.inline.} =
  ## Returns `true` if the scanner has reached the end of the source string.
  s.current >= s.source.len

proc match*(s: Scanner, expected: char): bool {.inline.} =
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

proc parseMdxComponent*(s: Scanner): Node =
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
  State = enum
    Normal
    InCodeFence
    InMdxTag
    InHeading

  Context = object
    state*: State
    stack*: seq[State]

proc parseMdxDocument*(s: Scanner): seq[Node] =
  # We keep a stack of states to handle nested elements: MDX components could
  # contain markdown which could contain MDX components.
  var context = Context(state: State.Normal, stack: @[])

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
