## Minimal GDScript parser specialized for code include shortcodes. Tokenizes symbol definitions and their body and collects all their content.
import std/[strutils, tables, unittest]
import std/times

type
  TokenType = enum
    Invalid
    Function
    Variable
    Constant
    Signal
    Class
    Enum

  Position = object
    index, line, column: int

  TokenRange = object
    start, `end`: Position
    definitionStart, definitionEnd: Position
    bodyStart, bodyEnd: Position

  Token = object
    tokenType: TokenType
    name: string
    range: TokenRange
    children: seq[Token]
    source: string

  Scanner = object
    # TODO: store source globally? So that we don't have to pass it around and any code can retrieve text from tokens
    source: string
    current: Position
    start: Position
    indentLevel: int
    bracketDepth: int
    peekIndex: int

proc peek(s: Scanner): char =
  ## Returns the current character without advancing the scanner's current index
  if s.current.index >= s.source.len:
    return '\0'
  return s.source[s.current.index]

proc advance(s: var Scanner): char =
  ## Advances the scanner by one character and returns the character
  ## Also, updates the current index, line, and column
  result = s.peek()
  if result != '\0':
    s.current.index += 1
    if result == '\n':
      s.current.line += 1
      s.current.column = 1
    else:
      s.current.column += 1

proc peekAt(s: var Scanner, offset: int): char =
  ## Peeks at a specific offset without advancing the scanner
  s.peekIndex = s.current.index + offset
  if s.peekIndex >= s.source.len:
    return '\0'
  return s.source[s.peekIndex]

proc peekString(s: var Scanner, expected: string): bool =
  ## Peeks ahead to check if the expected string is present without advancing
  for i in 0..<expected.len:
    if peekAt(s, i) != expected[i]:
      return false
  return true

proc advanceToPeek(s: var Scanner) =
  ## Advances the scanner to the stored peek index
  while s.current.index < s.peekIndex:
    discard s.advance()

proc match(s: var Scanner, expected: char): bool =
  ## Returns true and advances the scanner if and only if the current character matches the expected character
  ## Otherwise, returns false
  if s.peek() != expected:
    return false
  discard s.advance()
  true

proc matchString(s: var Scanner, expected: string): bool =
  ## Returns true and advances the scanner if and only if the next characters match the expected string
  if not peekString(s, expected):
    return false

  # If we found a match, advance the scanner by the length of the string
  for c in expected:
    discard s.advance()
  return true

proc countIndentation(s: var Scanner): int =
  ## Counts the number of spaces and tabs starting from the current position
  ## Call this function at the start of a line to count the indentation
  result = 0
  while true:
    case s.peek()
    of '\t':
      result += 1
      discard s.advance()
    of ' ':
      var spaces = 0
      while s.peek() == ' ':
        spaces += 1
        discard s.advance()
      result += spaces div 4
      break
    else:
      break
  return result

proc skipWhitespace(s: var Scanner) =
  ## Peeks at the next characters and advances the scanner until a non-whitespace character is found
  while true:
    let c = s.peek()
    case c:
    of ' ', '\r', '\t':
      discard s.advance()
    else:
      break

proc isAtEnd(s: Scanner): bool =
  # TODO: store length?
  s.current.index >= s.source.len

proc isAlphanumericOrUnderscore(c: char): bool =
  ## Returns true if the character is a letter, digit, or underscore
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit

proc scanIdentifier(s: var Scanner): int =
  let start = s.current.index
  while isAlphanumericOrUnderscore(s.peek()):
    discard s.advance()
  result = start

proc scanToEndOfLine(s: var Scanner): tuple[start, `end`: int] =
  let start = s.current.index
  while not s.isAtEnd() and s.peek() != '\n':
    discard s.advance()
  if not s.isAtEnd():
    discard s.advance()
  result = (start, s.current.index)

proc scanToEndOfDefinition(s: var Scanner): tuple[defStart, defEnd: int] =
  let start = s.current.index
  while not s.isAtEnd():
    let c = s.peek()
    case c
    of '(', '[', '{':
      s.bracketDepth += 1
      discard s.advance()
    of ')', ']', '}':
      s.bracketDepth -= 1
      discard s.advance()
      if s.bracketDepth == 0 and s.peek() == '\n':
        discard s.advance()
        break
    of '\n':
      discard s.advance()
      if s.bracketDepth == 0:
        break
    else:
      discard s.advance()
  result = (start, s.current.index)

proc isNewDefinition(s: var Scanner): bool =
  ## Returns true if there's a new definition ahead, regardless of its indent level
  ## or type
  let savedPos = s.current
  s.skipWhitespace()
  let firstChar = s.peek()
  # TODO: consider writing a proc to check for reserved keywords quickly instead of checking for the letter then keyword.
  result = (firstChar == 'f' and s.peekString("func")) or
            (firstChar == 'v' and s.peekString("var")) or
            (firstChar == 'c' and (s.peekString("const") or s.peekString("class"))) or
            (firstChar == 's' and s.peekString("signal")) or
            (firstChar == 'e' and s.peekString("enum"))
  s.current = savedPos
  return result

proc scanBody(s: var Scanner, startIndent: int): tuple[bodyStart, bodyEnd: int] =
  let start = s.current.index
  while not s.isAtEnd():
    let currentIndent = s.countIndentation()
    if currentIndent <= startIndent and not s.isAtEnd():
      if isNewDefinition(s):
        break

    let lineRange = scanToEndOfLine(s)
  result = (start, s.current.index)

proc scanToken(s: var Scanner): Token =
  s.start = s.current
  if s.isAtEnd():
    return Token(tokenType: TokenType.Invalid)

  s.indentLevel = s.countIndentation()
  s.skipWhitespace()

  let startPos = s.current
  let c = s.peek()
  case c
  of 'f':
    if s.matchString("func"):
      var token = Token(tokenType: TokenType.Function)
      token.range.start = startPos
      token.range.definitionStart = startPos

      s.skipWhitespace()
      let nameStart = s.scanIdentifier()
      token.name = s.source[nameStart..<s.current.index]

      while s.peek() != ':':
        discard s.advance()
      let lineRange = s.scanToEndOfLine()

      token.range.definitionEnd = s.current
      token.range.bodyStart = s.current

      discard s.scanBody(s.indentLevel)
      token.range.bodyEnd = s.current
      token.range.end = s.current

      return token
  of '@':
    var offset = 1
    var c2 = s.peekAt(offset)
    while c2 != '\n' and c2 != 'v':
      offset += 1
      c2 = s.peekAt(offset)

    if c2 == '\n':
      # This is an annotation on a single line, we skip this for now.
      s.advanceToPeek()
    if c2 == 'v':
      # Check if this is a variable definition, if so, create a var token,
      # and include the inline annotation in the definition
      s.advanceToPeek()
      if s.matchString("var"):
        var token = Token(tokenType: TokenType.Variable)
        token.range.start = startPos
        token.range.definitionStart = startPos

        s.skipWhitespace()
        let nameStart = s.scanIdentifier()
        token.name = s.source[nameStart..<s.current.index]

        discard s.scanToEndOfDefinition()
        token.range.end = s.current
        return token
  of 'v', 'c', 'e':
    var tokenType: TokenType
    if s.peekString("var"):
      tokenType = TokenType.Variable
      discard s.matchString("var")
    elif s.peekString("const"):
      tokenType = TokenType.Constant
      discard s.matchString("const")
    elif s.peekString("class"):
      tokenType = TokenType.Class
      discard s.matchString("class")
    elif s.peekString("enum"):
      tokenType = TokenType.Enum
      discard s.matchString("enum")
    else:
      discard s.advance()
      return Token(tokenType: TokenType.Invalid)

    var token = Token(tokenType: tokenType)
    token.range.start = startPos
    token.range.definitionStart = startPos

    s.skipWhitespace()
    let nameStart = s.scanIdentifier()
    token.name = s.source[nameStart..<s.current.index]

    discard s.scanToEndOfDefinition()
    token.range.end = s.current
    token.range.definitionEnd = s.current
    return token
  of 's':
    if s.matchString("signal"):
      var token = Token(tokenType: TokenType.Signal)
      token.range.start = startPos
      token.range.definitionStart = startPos

      s.skipWhitespace()
      let nameStart = s.scanIdentifier()
      token.name = s.source[nameStart..<s.current.index]

      # Handle signal arguments if present
      s.skipWhitespace()
      if s.peek() == '(':
        var bracketCount = 0
        while not s.isAtEnd():
          let c = s.peek()
          case c
          of '(':
            bracketCount += 1
            discard s.advance()
          of ')':
            bracketCount -= 1
            discard s.advance()
            if bracketCount == 0:
              break
          else:
            discard s.advance()
      else:
        discard s.scanToEndOfLine()

      token.range.end = s.current
      return token
  else:
    discard s.advance()

  Token(tokenType: TokenType.Invalid)

proc parseClass(s: var Scanner, classToken: var Token) =
  ## Parses the body of a class, collecting child tokens
  let classIndent = s.indentLevel
  s.current = classToken.range.bodyStart
  while not s.isAtEnd():
    let currentIndent = s.countIndentation()
    if currentIndent <= classIndent:
      if isNewDefinition(s):
        break

    let childToken = s.scanToken()
    if childToken.tokenType != TokenType.Invalid:
      classToken.children.add(childToken)

proc parseGDScript*(source: string): seq[Token] =
  var scanner =  Scanner(
    source: source,
    current: Position(index: 0, line: 1, column: 1),
    start: Position(index: 0, line: 1, column: 1),
    indentLevel: 0,
    bracketDepth: 0,
    peekIndex: 0
  )
  while not scanner.isAtEnd():
    var token = scanToken(scanner)
    if token.tokenType == TokenType.Invalid:
      continue

    if token.tokenType == TokenType.Class:
      token.range.bodyStart = scanner.current
      scanner.parseClass(token)
      token.range.bodyEnd = scanner.current
      token.range.end = scanner.current
    result.add(token)
proc printToken(token: Token, indent: int = 0) =
  let indentStr = "  ".repeat(indent)
  echo indentStr, "Token: ", $token.tokenType
  echo indentStr, "  Name: ", token.name
  echo indentStr, "  Range:"
  echo indentStr, "    Start: (line: ", token.range.start.line, ", col: ", token.range.start.column, ")"
  echo indentStr, "    End: (line: ", token.range.end.line, ", col: ", token.range.end.column, ")"

  if token.children.len > 0:
    echo indentStr, "  Children:"
    for child in token.children:
      printToken(child, indent + 2)

proc printTokens*(tokens: seq[Token]) =
  echo "Parsed Tokens:"
  for token in tokens:
    printToken(token)
    echo "" # Add a blank line between top-level tokens

proc runUnitTests() =
  suite "GDScript parser tests":
    test "Parse signals":
      let code =
        """
  signal health_depleted
  signal health_changed(old_health: int, new_health: int)
  """
      let tokens = parseGDScript(code)
      check:
        tokens.len == 2
      if tokens.len == 2:
        check:
          tokens[0].tokenType == TokenType.Signal
          tokens[0].name == "health_depleted"
          tokens[1].tokenType == TokenType.Signal
          tokens[1].name == "health_changed"

    test "Parse enums":
      let code =
        """
  enum Direction {UP, DOWN, LEFT, RIGHT}
  enum Events {
    NONE,
    FINISHED,
  }
  """
      let tokens = parseGDScript(code)
      check:
        tokens.len == 2
      if tokens.len == 2:
        check:
          tokens[0].tokenType == TokenType.Enum
          tokens[0].name == "Direction"
          tokens[1].tokenType == TokenType.Enum
          tokens[1].name == "Events"

    test "Parse variables":
      let code =
        """
@export var skin: MobSkin3D = null
@export_range(0.0, 10.0) var power := 0.1
var dynamic_uninitialized
var health := max_health
"""
      let tokens = parseGDScript(code)
      check:
        tokens.len == 4
      if tokens.len == 4:
        check:
          tokens[0].tokenType == TokenType.Variable
          tokens[0].name == "skin"
          tokens[1].tokenType == TokenType.Variable
          tokens[1].name == "power"
          tokens[2].tokenType == TokenType.Variable
          tokens[2].name == "dynamic_uninitialized"
          tokens[3].tokenType == TokenType.Variable
          tokens[3].name == "health"

    test "Parse constants":
      let code = "const MAX_HEALTH = 100"
      let tokens = parseGDScript(code)
      check:
        tokens.len == 1
      if tokens.len == 1:
        check:
          tokens[0].tokenType == TokenType.Constant
          tokens[0].name == "MAX_HEALTH"

    test "Parse functions":
      let code = """
func _ready():
	add_child(skin)

func deactivate() -> void:
	if hurt_box != null:
		(func deactivate_hurtbox():
			hurt_box.monitoring = false
			hurt_box.monitorable = false).call_deferred()
"""
      let tokens = parseGDScript(code)
      check:
        tokens.len == 2
      if tokens.len == 2:
        check:
          tokens[0].tokenType == TokenType.Function
          tokens[0].name == "_ready"
          tokens[1].tokenType == TokenType.Function
          tokens[1].name == "deactivate"
          # Instead of checking lines count, verify the ranges
          tokens[1].range.bodyStart.line < tokens[1].range.bodyEnd.line
          tokens[1].range.bodyEnd.line - tokens[1].range.bodyStart.line >= 4

    test "Parse inner class":
      let code = """
class StateMachine extends Node:
	var transitions := {}: set = set_transitions
	var current_state: State
	var is_debugging := false: set = set_is_debugging

	func _init() -> void:
		set_physics_process(false)
		var blackboard := Blackboard.new()
		Blackboard.player_died.connect(trigger_event.bind(Events.PLAYER_DIED))
"""
      let tokens = parseGDScript(code)
      check:
        tokens.len == 1
      if tokens.len == 1:
        let classToken = tokens[0]
        check:
          classToken.tokenType == TokenType.Class
          classToken.name == "StateMachine"
          classToken.children.len == 4
          classToken.children[0].tokenType == TokenType.Variable
          classToken.children[1].tokenType == TokenType.Variable
          classToken.children[2].tokenType == TokenType.Variable
          classToken.children[3].tokenType == TokenType.Function

    return
    test "Get class definition and body":
      let code = """
class Test extends Node:
	var x: int

	func test():
		pass
"""
      return
      #let tokens = parseGDScript(code)

      #let body = tokens[0].getBody()
      #let expected = "\tvar x: int\n\n\tfunc test():\n\t#\tpass"
      #check:
      #  tokens.len == 1
      #  tokens[0].tokenType == TokenType.Class
      #  tokens[0].getDefinition() == "class Test extends #Node:"
      #  body == expected

#when isMainModule:
#  runUnitTests()

let codeTest = """
class StateMachine extends Node:
	var transitions := {}: set = set_transitions
	var current_state: State
	var is_debugging := false: set = set_is_debugging

	func _init() -> void:
	set_physics_process(false)
	var blackboard := Blackboard.new()
	Blackboard.player_died.connect(trigger_event.bind(Events.PLAYER_DIED))
"""

echo "Running performance test..."
var totalDuration = 0.0
for i in 0..<10:
  let start = cpuTime()
  for j in 0..<10000:
    discard parseGDScript(codeTest)
  let duration = (cpuTime() - start) * 1000
  totalDuration += duration

let averageDuration = totalDuration / 10
echo "Average parse duration for 10 000 calls: ", averageDuration.formatFloat(ffDecimal, 3), "ms"
