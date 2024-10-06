## Minimal GDScript parser for code include shortcodes. Tokenizes functions, variables, and signals and collects all their content.
import std/[strutils, times, tables]

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

# TODO: make a func that directly finds and returns the line or line/col range of the definition?
proc isMultiLineDefinition(line: string): bool =
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

proc parseGDScript*(code: string): seq[Token] =
  var
    tokens: seq[Token] = @[]
    lines = code.splitLines()
    currentToken: Token
    isCollecting = false
    lineIndex = 0

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

  while lineIndex < lines.len:
    let line = lines[lineIndex]
    let (newDefinition, tokenType) = findDefinition(line)

    if newDefinition:
      if isCollecting:
        currentToken.range.lineEnd = lineIndex - 1
        tokens.add(currentToken)
        isCollecting = false

      currentToken = Token(
        tokenType: tokenType,
        name: extractName(line, tokenType),
        lines: @[line],
        range: Range(lineStart: lineIndex, lineEnd: -1),
      )

      if isMultiLineDefinition(line):
        isCollecting = true
      else:
        currentToken.range.lineEnd = lineIndex
        tokens.add(currentToken)
    elif isCollecting:
      currentToken.lines.add(line)

    lineIndex += 1

  # Collect the last token
  if isCollecting:
    currentToken.range.lineEnd = lineIndex - 1
    tokens.add(currentToken)
    isCollecting = false

  # Remove empty lines from the end of each token
  for token in tokens.mitems():
    while token.lines.len > 0 and token.lines[^1].isEmptyOrWhitespace:
      token.lines.setLen(token.lines.len - 1)

  return tokens

let testCode =
  """
class_name AI extends RefCounted

signal health_depleted
signal health_changed(old_health: int, new_health: int)

enum Direction {UP, DOWN, LEFT, RIGHT}
enum Events {
	NONE,
	FINISHED,
}

@export var skin: MobSkin3D = null
@export var hurt_box: HurtBox3D = null

var health := max_health

const MAX_HEALTH = 100

func deactivate() -> void:
	if hurt_box != null:
		(func deactivate_hurtbox():
			hurt_box.monitoring = false
			hurt_box.monitorable = false).call_deferred()


class StateMachine extends Node:
	var transitions := {}: set = set_transitions
	var current_state: State
	var is_debugging := false: set = set_is_debugging

	func _init() -> void:
		set_physics_process(false)
		var blackboard := Blackboard.new()
		Blackboard.player_died.connect(trigger_event.bind(Events.PLAYER_DIED))

func _ready():
	add_child(skin)
"""

when isMainModule:
  let start = cpuTime()
  for i in 0 .. 10_000:
    discard parseGDScript(testCode)
  let duration = cpuTime() - start
  echo "Time taken to parse 10 000 times: ", duration, " seconds"

  # TODO: use test cases
  let tokens = parseGDScript(testCode)
  for token in tokens:
    echo "Type: ", token.tokenType
    echo "Name: ", token.name
    echo "Range: ", token.range.lineStart, " - ", token.range.lineEnd
    echo "Content:"
    echo token.lines.join("\n")
    echo "---"
