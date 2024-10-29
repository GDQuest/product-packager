## Minimal GDScript parser specialized for code include shortcodes. Tokenizes symbol definitions and their body and collects all their content.
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

# TODO: extract multiline definitions
proc getDefinition*(token: Token): string =
  if token.tokenType in {TokenType.Function, TokenType.Class}:
    return token.lines[0]
  else:
    raise newException(
      ValueError,
      # NB: the $ operator stringifies the token type.
      "Trying to call getDefinition for an unsupported token type. tokenType is: " &
        $token.tokenType,
    )

proc getBody*(token: Token): string =
  if token.tokenType == TokenType.Function or token.tokenType == TokenType.Class:
    # TODO: handle cases where function definition is multiline.
    return token.lines[1 ..^ -1].join("\n")
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
  var isTab = line.len > 0 and line[0] == '\t'
  let indentChar = if isTab: '\t' else: ' '
  for c in line:
    if c == indentChar:
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

# TODO: consider moving to a scanner and capturing definitions through a state machine. E.g. a func definition is
# func + ( + ) + : + \n
# Consider recursive parsing too: e.g. capturing a class whole and then parsing its body in a separate step.
# Instead of trying to capture all at once, this could work in two passes:
# 1. Tokenize and capture indices and line numbers with a scanner.
# 2. Parse the tokens and build a tree.
#
# Currently, the parser tries to both tokenize and separate definitions at once.
# This different algorithm would allow capturing the definitions and bodies in one scan pass.
# Also we wouldn't need to copy the lines to the tokens, we could just store the character ranges.
proc parseGDScript*(code: string): seq[Token] =
  let lines = code.splitLines()
  var
    tokens: seq[Token] = @[]
    currentToken: Token
    isCollecting = false
    lineIndex = 0
    currentIndent = 0
    lastDefinitionIndent = 0
    isInsideFunction = false
    lastFunctionDefinitionIndent = 0
    isInsideClass = false
    classStartIndent = 0

  proc collectToken() =
    if currentToken.tokenType != TokenType.Class:
      if currentIndent > lastDefinitionIndent and tokens.len > 0 and
          tokens[^1].tokenType == TokenType.Class:
        tokens[^1].children.add(currentToken)
      else:
        tokens.add(currentToken)
    else:
      tokens.add(currentToken)

  proc parseClassBody(classToken: var Token, startLine: int): int =
    # Parse the class body and collect both lines and child tokens.
    # This function exists due to how I initially implemented the parser and could be removed
    # by going for a scanner architecture, going character by character.
    # Classes don't fit the original algorithm, they need to collect both child tokens and all lines in their
    # body, including empty lines between child tokens (which aren't parsed otherwise)
    var classLineIndex = startLine

    while classLineIndex < lines.len:
      let line = lines[classLineIndex]
      let lineIndent = getIndentLevel(line)

      # Check if we're still in class scope, if not, we finished reading the class body.
      let isEndOfClass = not line.isEmptyOrWhitespace() and lineIndent == 0
      if isEndOfClass:
        return classLineIndex - 1

      # Parse child definitions within the class
      let (isNewDefinition, tokenType) = findDefinition(line)
      let isClassChild = isNewDefinition and lineIndent == 1
      if isClassChild:
        var childToken = Token(
          tokenType: tokenType,
          name: extractName(line, tokenType),
          lines: @[line],
          range: Range(lineStart: classLineIndex, lineEnd: -1)
        )

        if tokenType == TokenType.Function or isMultiLineDefinition(line):
          classLineIndex += 1
          let childIndent = lineIndent
          while classLineIndex < lines.len:
            let childLine = lines[classLineIndex]
            let childLineIndent = getIndentLevel(childLine)
            # Stop if we find another definition at the same indent level, or a lesser indent
            let (foundNextDef, _) = findDefinition(childLine)
            if not childLine.isEmptyOrWhitespace() and (
              childLineIndent <= childIndent or
              (childLineIndent == childIndent + 1 and foundNextDef)
            ):
              break
            childToken.lines.add(childLine)
            classLineIndex += 1

          classLineIndex -= 1
          childToken.range.lineEnd = classLineIndex
        else:
          childToken.range.lineEnd = classLineIndex

        classToken.children.add(childToken)

      classLineIndex += 1

    return classLineIndex - 1

  while lineIndex < lines.len:
    let line = lines[lineIndex]
    currentIndent = getIndentLevel(line)

    let (isNewDefinition, tokenType) = findDefinition(line)
    if isNewDefinition:
      # We don't want to collect local definitions, so we skip them.
      let isFunctionLocalDefinition = isInsideFunction and currentIndent > lastFunctionDefinitionIndent
      if isFunctionLocalDefinition:
        lineIndex += 1
        continue

      if isCollecting and not isInsideClass:
        currentToken.range.lineEnd = lineIndex - 1
        if not isInsideFunction or currentIndent <= lastFunctionDefinitionIndent:
          collectToken()
        isCollecting = false

      currentToken = Token(
        tokenType: tokenType,
        name: extractName(line, tokenType),
        lines: @[line],
        range: Range(lineStart: lineIndex, lineEnd: -1),
      )

      # For classes, we parse the body separately. This is due to how I
      # approached the parsing algorithm initially, as I tried to tokenize per
      # definition. See the comments at the top of the function for a different
      # approach.
      if tokenType == TokenType.Class:
        currentToken.range.lineStart = lineIndex
        lineIndex = parseClassBody(currentToken, lineIndex + 1)
        currentToken.range.lineEnd = lineIndex
        for index in (currentToken.range.lineStart + 1)..currentToken.range.lineEnd:
          let classLine = lines[index]
          currentToken.lines.add(classLine)
        collectToken()
      elif not isInsideFunction and tokenType == TokenType.Function:
        isInsideFunction = true
        lastFunctionDefinitionIndent = currentIndent
      elif currentIndent <= lastFunctionDefinitionIndent:
        isInsideFunction = false

      if isMultiLineDefinition(line) and tokenType != TokenType.Class:
        isCollecting = true
        lastDefinitionIndent = currentIndent
      elif tokenType != TokenType.Class:
        currentToken.range.lineEnd = lineIndex
        if not isInsideFunction or currentIndent <= lastFunctionDefinitionIndent:
          collectToken()
          if tokens[^1].tokenType != TokenType.Class:
            lastDefinitionIndent = currentIndent
    elif isCollecting and not isInsideClass:
      currentToken.lines.add(line)

    lineIndex += 1

  # Collect the last token
  if isCollecting and not isInsideClass:
    currentToken.range.lineEnd = lineIndex - 1
    collectToken()

  proc removeTrailingEmptyLines(token: var Token) =
    # Remove empty lines from the end of each token
    while token.lines.len > 0 and token.lines[^1].isEmptyOrWhitespace:
      token.lines.setLen(token.lines.len - 1)
    for child in token.children.mitems:
      removeTrailingEmptyLines(child)

  for token in tokens.mitems:
    removeTrailingEmptyLines(token)

  for token in tokens:
    printToken(token)
  return tokens

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
      let body = tokens[0].getBody()
      let expected = "\tvar x: int\n\n\tfunc test():\n\t\tpass"
      # TODO: issue is that empty lines between definitions are not tokenized so the line return is missing
      echo "Got body: [\n", body, "]"
      echo "Expected: [\n", expected, "]"
      check:
        tokens.len == 1
        tokens[0].tokenType == TokenType.Class
        tokens[0].getDefinition() == "class Test extends Node:"
        body == expected

# Unit tests
when isMainModule:
  runUnitTests()
