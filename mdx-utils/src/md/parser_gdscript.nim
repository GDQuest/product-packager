## Minimal GDScript parser specialized for code include shortcodes. Tokenizes symbol definitions and their body and collects all their content.
# FIXME: if a file starts with a class definition, following tokens are not collected as children of the class.
# TODO: functions: add functions to get the definition and body of the token.
# TODO: class: add functions to get the definition and body of the token. Definition is the class token content, body is the formatted children tokens.
import std/[strutils, tables, unittest]

type
  TokenType = enum
    Function
    Variable
    Constant
    Signal
    Class
    Enum

  Range = object
    lineStart: int
    lineEnd: int

  Token = object
    tokenType: TokenType
    name: string
    lines: seq[string] = @[]
    range: Range
    children: seq[Token] = @[]

  TokenFunction =
    concept t
        t is Token
        t.tokenType == TokenType.Function

  TokenClass =
    concept t
        t is Token
        t.tokenType == TokenType.Class

# TODO: extract multiline definitions
proc getDefinition*(token: Token): string =
  if token is TokenFunction or token is TokenClass:
    return token.lines[0]
  else:
    raise newException(
      ValueError,
      # NB: the $ operator stringifies the token type.
      "Trying to call getDefinition for an unsupported token type. tokenType is: " &
        $token.tokenType,
    )

proc getBody*(token: Token): string =
  if token is TokenFunction:
    # TODO: handle cases where function definition is multiline.
    return token.lines[1 ..^ 1].join("\n")
  elif token is TokenClass:
    var bodyLines: seq[string] = @[]
    for child in token.children:
      bodyLines.add(child.lines)
    return bodyLines.join("\n")
  else:
    raise newException(
      ValueError,
      "Trying to call getBody for an unsupported token type. tokenType is: " &
        $token.tokenType,
    )

const
  DEFINITION_KEYWORDS = ["func", "var", "const", "signal", "class", "enum"]
  MULTI_LINE_ENDINGS = {':', '=', '(', '\\'}
  BRACKET_OPENINGS = {'(', '{', '['}
  BRACKET_CLOSINGS = {')', '}', ']'}
  KEYWORD_TO_TOKEN_TYPE = {
    "func": TokenType.Function,
    "var": TokenType.Variable,
    "const": TokenType.Constant,
    "signal": TokenType.Signal,
    "class": TokenType.Class,
    "enum": TokenType.Enum,
  }.toTable()

proc isMultiLineDefinition(line: string): bool =
  ## Returns true if the definition contained in `line` spans multiple lines.
  ## This is for example a variable with a dictionary or array definition formatted over multiple lines.
  let stripped = line.strip()
  if stripped.isEmptyOrWhitespace():
    return false

  let lastChar = stripped[^1]
  if lastChar in MULTI_LINE_ENDINGS:
    return true

  # Walk the line and look for a bracket pair. If there's an opening bracket but no closing bracket,
  # then it's a multi-line definition.
  var bracketCount = 0
  for c in stripped:
    if c in BRACKET_OPENINGS:
      bracketCount += 1
    elif c in BRACKET_CLOSINGS:
      bracketCount -= 1

  return bracketCount > 0

proc findDefinition(line: string): tuple[isDefinition: bool, tokenType: TokenType] =
  ## Tries to find a definition in the line. Returns a tuple with a boolean indicating if a definition was found
  ## and the token type of the definition.
  var stripped = line.strip(trailing = false)

  # Skip annotation if present
  if stripped.startsWith('@'):
    let annotationEnd = stripped.find(')')
    if annotationEnd != -1:
      stripped = stripped[annotationEnd + 1 ..^ 1].strip(leading = true)
    else:
      stripped = stripped.split(maxsplit = 1)[^1].strip(leading = true)

  var firstWordEnd = 0
  for c in stripped:
    if c == ' ':
      break
    firstWordEnd += 1
  let firstWord = stripped[0 .. firstWordEnd - 1]
  let foundIndex = DEFINITION_KEYWORDS.find(firstWord)
  result.isDefinition = foundIndex != -1
  if result.isDefinition:
    result.tokenType = KEYWORD_TO_TOKEN_TYPE[firstWord]

proc getIndentLevel(line: string): int =
  # GDScript either uses tabs or 4 spaces for indentation. So we can count
  # either 1 tab per indent or 4 spaces per indent.
  result = 0
  var isTab = false
  for c in line:
    if c == '\t':
      isTab = true
      result += 1
    elif c == ' ':
      result += 1
    else:
      break
  if not isTab:
    result = result.div(4)
  return result

proc extractName(lineDefinition: string, tokenType: TokenType): string =
  ## Extracts the name of the definition from the line.
  let length = lineDefinition.len()
  var nameStart = 0
  if tokenType == TokenType.Variable:
    nameStart = lineDefinition.find("var ") + 4
  else:
    let parts = lineDefinition.split(maxsplit = 1)
    nameStart = parts[0].len()

  while nameStart < length and lineDefinition[nameStart] == ' ':
    nameStart += 1
  var nameEnd = length - 1
  for i in nameStart .. lineDefinition.high():
    if lineDefinition[i] in {' ', ':', '=', '(', '{'}:
      nameEnd = i - 1
      break
  result = lineDefinition[nameStart .. nameEnd].strip()

#TODO: ignore local variables, constants, functions, ...
# locals are any definition when collecting a function that have an indent greater than the function definition.
proc parseGDScript*(code: string): seq[Token] =
  let lines = code.splitLines()
  var
    tokens: seq[Token] = @[]
    currentToken: Token
    isCollecting = false
    lineIndex = 0
    currentIndent = 0
    lastDefinitionIndent = 0
    isInsideFunction = false # New flag to track if we're inside a function
    lastFunctionDefinitionIndent = 0

  while lineIndex < lines.len:
    let line = lines[lineIndex]
    if line.isEmptyOrWhitespace():
      lineIndex += 1
      continue

    currentIndent = getIndentLevel(line)
    let (isNewDefinition, tokenType) = findDefinition(line)

    if isNewDefinition:
      if isCollecting:
        currentToken.range.lineEnd = lineIndex - 1
        # Only tokenize non-local definitions
        if not isInsideFunction or currentIndent <= lastFunctionDefinitionIndent:
          if currentIndent > lastDefinitionIndent and tokens.len > 0 and
              tokens[^1].tokenType == TokenType.Class:
            tokens[^1].children.add(currentToken)
          else:
            tokens.add(currentToken)
        isCollecting = false

      currentToken = Token(
        tokenType: tokenType,
        name: extractName(line, tokenType),
        lines: @[line],
        range: Range(lineStart: lineIndex, lineEnd: -1),
      )

      # FIXME: now this won't collect functions that we do want to collect.
      if not isInsideFunction and tokenType == TokenType.Function:
        isInsideFunction = true
        lastFunctionDefinitionIndent = currentIndent
      elif currentIndent <= lastFunctionDefinitionIndent:
        isInsideFunction = false

      if isMultiLineDefinition(line):
        isCollecting = true
        lastDefinitionIndent = currentIndent
      else:
        currentToken.range.lineEnd = lineIndex
        if not isInsideFunction or currentIndent <= lastFunctionDefinitionIndent:
          if currentIndent > lastDefinitionIndent and tokens.len > 0 and
              tokens[^1].tokenType == TokenType.Class:
            tokens[^1].children.add(currentToken)
          else:
            tokens.add(currentToken)
            lastDefinitionIndent = currentIndent
    elif isCollecting:
      currentToken.lines.add(line)

    lineIndex += 1

  # Collect the last token
  # TODO: check this after adding checks for local variables
  if isCollecting:
    currentToken.range.lineEnd = lineIndex - 1

    if currentIndent > lastDefinitionIndent and tokens.len > 0 and
        tokens[^1].tokenType == TokenType.Class:
      tokens[^1].children.add(currentToken)
    else:
      tokens.add(currentToken)

  # Remove empty lines from the end of each token
  proc removeTrailingEmptyLines(token: var Token) =
    while token.lines.len > 0 and token.lines[^1].isEmptyOrWhitespace:
      token.lines.setLen(token.lines.len - 1)
    for child in token.children.mitems:
      removeTrailingEmptyLines(child)

  for token in tokens.mitems:
    removeTrailingEmptyLines(token)

  return tokens

proc printToken(token: Token, isIndented: bool = false) =
  ## Prints a token and its children.
  let indentStr = if isIndented: "\t" else: ""
  echo indentStr, "Type: ", token.tokenType
  echo indentStr, "Name: ", token.name
  echo indentStr, "Range: ", token.range.lineStart, " - ", token.range.lineEnd
  echo indentStr, "Content:"
  for line in token.lines:
    echo indentStr, line
  if token.tokenType == TokenType.Class:
    for child in token.children:
      printToken(child, isIndented = true)
  echo indentStr, "---"

proc runUnitTests() =
  ## Note: when adding tests, be careful to make the code use tabs or four spaces for indentation.
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
        tokens[0].tokenType == TokenType.Enum
        tokens[0].name == "Direction"
        tokens[1].tokenType == TokenType.Enum
        tokens[1].name == "Events"
        tokens[1].lines.len == 4

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
        tokens[0].tokenType == TokenType.Constant
        tokens[0].name == "MAX_HEALTH"

    test "Parse functions":
      let code =
        """
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
          tokens[1].lines.len == 5

    test "Parse inner class":
      let code =
        """
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

      if tokens.len > 0:
        let classToken = tokens[0]
        check:
          classToken.tokenType == TokenType.Class
          classToken.name == "StateMachine"
          classToken.children.len == 4

        if classToken.children.len >= 4:
          check:
            classToken.children[0].tokenType == TokenType.Variable
            classToken.children[1].tokenType == TokenType.Variable
            classToken.children[2].tokenType == TokenType.Variable
            classToken.children[3].tokenType == TokenType.Function

    test "Get class definition and body":
      let code =
        """
class Test extends Node:
	var x: int

	func test():
		pass
"""
      let tokens = parseGDScript(code)
      check:
        tokens.len == 1
        tokens[0].tokenType == TokenType.Class
        tokens[0] is TokenClass
        tokens[0].getDefinition() == "class Test extends Node:"
        tokens[0].getBody() == "  var x: int\n\n  func test():\n    pass"

# Unit tests
when isMainModule:
  runUnitTests()
