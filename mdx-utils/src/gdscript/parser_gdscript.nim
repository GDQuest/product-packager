## Minimal GDScript parser specialized for code include shortcodes. Tokenizes symbol definitions and their body and collects all their content.
import std/[strutils, tables, unittest]
import std/times
when compileOption("profiler"):
  import std/nimprof

type
  TokenType = enum
    Invalid
    Function
    Variable
    Constant
    Signal
    Class
    Enum

  TokenRange = object
    # Start and end character positions of the entire token (definition + body if applicable) in the source code
    start, `end`: int
    definitionStart, definitionEnd: int
    bodyStart, bodyEnd: int

  Token = object
    tokenType: TokenType
    nameStart, nameEnd: int
    range: TokenRange
    children: seq[Token]

  Scanner = object
    # TODO: Cache the source elsewhere for reading the content of tokens after parsing.
    source: string
    current: int
    indentLevel: int
    bracketDepth: int
    peekIndex: int

proc getCurrentChar(s: Scanner): char {.inline.} =
  ## Returns the current character without advancing the scanner's current index
  return s.source[s.current]

proc advance(s: var Scanner): char {.inline.} =
  ## Reads and returns the current character, then advances the scanner by one
  result = s.source[s.current]
  s.current += 1

proc peekAt(s: var Scanner, offset: int): char {.inline.} =
  ## Peeks at a specific offset and returns the character without advancing the scanner
  s.peekIndex = s.current + offset
  if s.peekIndex >= s.source.len:
    return '\0'
  return s.source[s.peekIndex]

proc peekString(s: var Scanner, expected: string): bool {.inline.} =
  ## Peeks ahead to check if the expected string is present without advancing
  ## Returns true if the string is found, false otherwise
  let length = expected.len
  for i in 0..<length:
    if peekAt(s, i) != expected[i]:
      return false
  s.peekIndex = s.current + length
  return true

proc advanceToPeek(s: var Scanner) {.inline.} =
  ## Advances the scanner to the stored getCurrentChar index
  s.current = s.peekIndex

proc match(s: var Scanner, expected: char): bool {.inline.} =
  ## Returns true and advances the scanner if and only if the current character matches the expected character
  ## Otherwise, returns false
  if s.getCurrentChar() != expected:
    return false
  discard s.advance()
  return true

proc matchString(s: var Scanner, expected: string): bool {.inline.} =
  ## Returns true and advances the scanner if and only if the next characters match the expected string
  if s.peekString(expected):
    s.advanceToPeek()
    return true
  return false

proc countIndentation(s: var Scanner): int {.inline.} =
  ## Counts the number of spaces and tabs starting from the current position
  ## Call this function at the start of a line to count the indentation
  result = 0
  while true:
    case s.getCurrentChar()
    of '\t':
      result += 1
      s.current += 1
    of ' ':
      var spaces = 0
      while s.getCurrentChar() == ' ':
        spaces += 1
        s.current += 1
      result += spaces div 4
      break
    else:
      break
  return result

proc skipWhitespace(s: var Scanner) {.inline.} =
  ## Peeks at the next characters and advances the scanner until a non-whitespace character is found
  while true:
    let c = s.getCurrentChar()
    case c:
    of ' ', '\r', '\t':
      discard s.advance()
    else:
      break

proc isAtEnd(s: Scanner): bool {.inline.} =
  s.current >= s.source.len

proc isAlphanumericOrUnderscore(c: char): bool {.inline.} =
  ## Returns true if the character is a letter, digit, or underscore
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit

proc scanIdentifier(s: var Scanner): tuple[start: int, `end`: int] {.inline.} =
  let start = s.current
  while isAlphanumericOrUnderscore(s.getCurrentChar()):
    discard s.advance()
  result = (start, s.current)

proc scanToEndOfLine(s: var Scanner): tuple[start, `end`: int] {.inline.} =
  let start = s.current
  let length = s.source.len
  var offset = 0
  var c = s.source[s.current]
  while c != '\n':
    offset += 1
    if s.current + offset >= length:
      break
    c = s.source[s.current + offset]
  s.current += offset
  if s.current < length:
    discard s.advance()
  result = (start, s.current)

proc scanToEndOfDefinition(s: var Scanner): tuple[defStart, defEnd: int] {.inline.} =
  let start = s.current
  while not s.isAtEnd():
    let c = s.getCurrentChar()
    case c
    of '(', '[', '{':
      s.bracketDepth += 1
      discard s.advance()
    of ')', ']', '}':
      s.bracketDepth -= 1
      discard s.advance()
      if s.bracketDepth == 0 and s.getCurrentChar() == '\n':
        discard s.advance()
        break
    of '\n':
      discard s.advance()
      if s.bracketDepth == 0:
        break
    else:
      discard s.advance()
  result = (start, s.current)

proc isNewDefinition(s: var Scanner): bool {.inline.} =
  ## Returns true if there's a new definition ahead, regardless of its indent level
  ## or type
  let savedPos = s.current
  s.skipWhitespace()
  let firstChar = s.getCurrentChar()
  result = s.peekString("func") or
           s.peekString("var") or
           s.peekString("const") or
           s.peekString("class") or
           s.peekString("signal") or
           s.peekString("enum")
  s.current = savedPos
  return result

proc scanBody(s: var Scanner, startIndent: int): tuple[bodyStart, bodyEnd: int] =
  let start = s.current
  while not s.isAtEnd():
    let currentIndent = s.countIndentation()
    if currentIndent <= startIndent and not s.isAtEnd():
      if isNewDefinition(s):
        break

    discard scanToEndOfLine(s)
  result = (start, s.current)

proc scanToken(s: var Scanner): Token =
  if s.isAtEnd():
    return Token(tokenType: TokenType.Invalid)

  s.indentLevel = s.countIndentation()
  s.skipWhitespace()

  let startPos = s.current
  let c = s.getCurrentChar()
  case c
  # Function definition
  of 'f':
    if s.matchString("func"):
      var token = Token(tokenType: TokenType.Function)
      token.range.start = startPos
      token.range.definitionStart = startPos

      s.skipWhitespace()
      let (nameStart, nameEnd) = s.scanIdentifier()
      token.nameStart = nameStart
      token.nameEnd = nameEnd

      while s.getCurrentChar() != ':':
        discard s.advance()
      discard s.scanToEndOfLine()

      token.range.definitionEnd = s.current
      token.range.bodyStart = s.current

      discard s.scanBody(s.indentLevel)
      token.range.bodyEnd = s.current
      token.range.end = s.current

      return token
  # Annotation
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

        let (nameStart, nameEnd) = s.scanIdentifier()
        token.nameStart = nameStart
        token.nameEnd = nameEnd

        discard s.scanToEndOfDefinition()
        token.range.end = s.current
        return token
  # Variable, Constant, Class, Enum
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

    let (nameStart, nameEnd) = s.scanIdentifier()
    token.nameStart = nameStart
    token.nameEnd = nameEnd

    discard s.scanToEndOfDefinition()
    token.range.end = s.current
    token.range.definitionEnd = s.current
    return token
  # Signal
  of 's':
    if s.matchString("signal"):
      var token = Token(tokenType: TokenType.Signal)
      token.range.start = startPos
      token.range.definitionStart = startPos

      s.skipWhitespace()

      let (nameStart, nameEnd) = s.scanIdentifier()
      token.nameStart = nameStart
      token.nameEnd = nameEnd

      # Handle signal arguments if present
      s.skipWhitespace()
      if s.getCurrentChar() == '(':
        var bracketCount = 0
        while not s.isAtEnd():
          let c = s.getCurrentChar()
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
    current: 0,
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

proc getName(token: Token, source: string): string {.inline.} =
  return source[token.nameStart ..< token.nameEnd]

proc getBody(token: Token, source: string): string {.inline.} =
  return source[token.range.bodyStart ..< token.range.bodyEnd]

proc printToken(token: Token, source: string, indent: int = 0) =
  let indentStr = "  ".repeat(indent)
  echo indentStr, "Token: ", $token.tokenType
  echo indentStr, "  Name: ", getName(token, source)
  echo indentStr, "  Range:"
  echo indentStr, "    Start: ", token.range.start
  echo indentStr, "    End: ", token.range.end

  if token.children.len > 0:
    echo indentStr, "  Children:"
    for child in token.children:
      printToken(child, source, indent + 2)

proc printTokens*(tokens: seq[Token], source: string) =
  echo "Parsed Tokens:"
  for token in tokens:
    printToken(token, source)
    echo ""

proc runPerformanceTest() =
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
          tokens[0].getName(code) == "health_depleted"
          tokens[1].tokenType == TokenType.Signal
          tokens[1].getName(code) == "health_changed"

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
          tokens[0].getName(code) == "Direction"
          tokens[1].tokenType == TokenType.Enum
          tokens[1].getName(code) == "Events"

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
          tokens[0].getName(code) == "skin"
          tokens[1].tokenType == TokenType.Variable
          tokens[1].getName(code) == "power"
          tokens[2].tokenType == TokenType.Variable
          tokens[2].getName(code) == "dynamic_uninitialized"
          tokens[3].tokenType == TokenType.Variable
          tokens[3].getName(code) == "health"

    test "Parse constants":
      let code = "const MAX_HEALTH = 100"
      let tokens = parseGDScript(code)
      check:
        tokens.len == 1
      if tokens.len == 1:
        check:
          tokens[0].tokenType == TokenType.Constant
          tokens[0].getName(code) == "MAX_HEALTH"

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
          tokens[0].getName(code) == "_ready"
          tokens[1].tokenType == TokenType.Function
          tokens[1].getName(code) == "deactivate"

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
          classToken.getName(code) == "StateMachine"
          classToken.children.len == 4
          classToken.children[0].tokenType == TokenType.Variable
          classToken.children[1].tokenType == TokenType.Variable
          classToken.children[2].tokenType == TokenType.Variable
          classToken.children[3].tokenType == TokenType.Function

when isMainModule:
  runUnitTests()
  #runPerformanceTest()
