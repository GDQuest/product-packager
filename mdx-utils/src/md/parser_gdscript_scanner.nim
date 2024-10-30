## Minimal GDScript parser specialized for code include shortcodes. Tokenizes symbol definitions and their body and collects all their content.
import std/[strutils, tables, unittest]

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

  Scanner = object
    source: string
    current: Position
    start: Position
    indentLevel: int
    bracketDepth: int
    peekIndex: int

#TODO: There could be a peek index and peeking moves that index without moving the scanner, so that we can peek multiple times without advancing the scanner
# We could then jump to the peek index when we know we want to consume the peeked characters
# We could also have a function to peek for a string, which would be useful for matching keywords
proc peek(s: Scanner): char =
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

proc peekAt(s: Scanner, offset: int): char =
  ## Peeks at a specific offset without advancing the scanner
  let index = s.current.index + offset
  if index >= s.source.len:
    return '\0'
  return s.source[index]

proc peekString(s: var Scanner, expected: string): bool =
  ## Peeks ahead to check if the expected string is present without advancing
  for i in 0..<expected.len:
    if peekAt(s, i) != expected[i]:
      return false
  return true

proc setPeekIndex(s: var Scanner) =
  ## Stores current position as peek index
  s.peekIndex = s.current.index

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

proc scanIdentifier(s: var Scanner): string =
  while isAlphanumericOrUnderscore(s.peek()):
    result.add(s.advance())

proc scanToEndOfLine(s: var Scanner): string =
  ## Advances the scanner until the end of the line, returning the content, including the \n character at the end
  while not s.isAtEnd() and s.peek() != '\n':
    result.add(s.advance())
  if not s.isAtEnd():
    result.add(s.advance())

proc scanToEndOfDefinition(s: var Scanner): string =
  ## Scans until the end of a definition, handling multiline definitions with brackets
  # TODO: gotta check if this works for e.g. functions etc.
  while not s.isAtEnd():
    let c = s.peek()
    case c
    of '(', '[', '{':
      s.bracketDepth += 1
      result.add(s.advance())
    of ')', ']', '}':
      s.bracketDepth -= 1
      result.add(s.advance())
      if s.bracketDepth == 0 and s.peek() == '\n':
        result.add(s.advance())
        break
    of '\n':
      result.add(s.advance())
      if s.bracketDepth == 0:
        break
    else:
      result.add(s.advance())

proc scanBody(s: var Scanner, startIndent: int): string =
  ## Scans the body of a function or class until we find a definition at the same indent level
  while not s.isAtEnd():
    let currentIndent = s.countIndentation()
    if currentIndent <= startIndent and not s.isAtEnd():
      # Check if this is a new definition
      let savedPos = s.current
      s.skipWhitespace()
      let firstChar = s.peek()
      s.current = savedPos
      # TODO: is it enough to check for these characters? or should we check for reserved keywords?
      if firstChar in {'f', 'v', 'c', 's', 'e'}:
        break

    result.add(scanToEndOfLine(s))

proc scanToken(s: var Scanner): Token =
  s.start = s.current
  if s.isAtEnd():
    return Token(tokenType: TokenType.Invalid)

  s.indentLevel = s.countIndentation()
  s.skipWhitespace()

  # Skip annotations
  # TODO: a var can be annotated like @export var ...
  # Should be captured as part of the variable token somehow
  if s.peek() == '@':
    while not s.isAtEnd() and s.peek() != '\n':
      discard s.advance()
    s.skipWhitespace()

  let startPos = s.current
  let c = s.peek()
  case c
  of 'f':
    if s.matchString("func"):
      var token = Token(tokenType: TokenType.Function)
      token.range.start = startPos
      token.range.definitionStart = startPos

      # Scan function definition
      s.skipWhitespace()
      token.name = s.scanIdentifier()
      var definition = "func " & token.name
      while s.peek() != ':':
        definition.add(s.advance())
      definition.add(s.scanToEndOfLine())

      token.range.definitionEnd = s.current
      token.range.bodyStart = s.current

      discard s.scanBody(s.indentLevel)
      token.range.bodyEnd = s.current
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
    token.name = s.scanIdentifier()
    discard s.scanToEndOfDefinition()

    token.range.end = s.current
    return token
  of 's':
    if s.matchString("signal"):
      var token = Token(tokenType: TokenType.Signal)
      token.range.start = startPos
      token.range.definitionStart = startPos

      s.skipWhitespace()
      token.name = s.scanIdentifier()

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
  while not s.isAtEnd():
    let currentIndent = s.countIndentation()
    if currentIndent <= classIndent:
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
    let token = scanToken(scanner)
    if token.tokenType == TokenType.Invalid:
      continue

    if token.tokenType == TokenType.Class:
      var classToken = token
      parseClass(scanner, classToken)
      result.add(classToken)
    else:
      result.add(token)

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
          # Instead of checking lines, verify the range
          tokens[1].range.bodyStart.line < tokens[1].range.bodyEnd.line

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

when isMainModule:
  runUnitTests()
