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

  proc isDefinition(line: string): tuple[isDefinition: bool, tokenType: TokenType] =
    ## Returns true if the line is a definition line.
    let stripped = line.strip(trailing = false)
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

proc parseGDScript*(code: string): seq[Token] =
  var
    tokens: seq[Token] = @[]
    lines = code.splitLines()
    currentToken: Token
    isCollecting = false
    indentLevel = 0

  proc isKeyword(line: string): bool =
    let stripped = line.strip()
    stripped.startsWith("func ") or stripped.startsWith("var ") or
      stripped.startsWith("const ") or stripped.startsWith("signal ") or
      stripped.startsWith("class ") or stripped.startsWith("enum ")

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

  # This code iterates through the lines and when finding a token,
  # it collects the content of the token until the next token is found.

  # TODO: rewrite algorithm. It should:
  # - Check if a line is a definition.
  #     - If so, check if it's a multi-line definition.
  #     - If not, make a token with the line, otherwise, collect lines until the next definition or end of file.
  # - Separately, parse the collected content of the token:
  #     - For classes and functions, Separate the definition from the body.
  #     - For classes, parse child functions, variables, constants, signals, and enums. Assume a single level of nesting.
  #     - For variables, constants, signals, and enums just collect the lines.
  for i, line in lines:
    let trimmedLine = line.strip()
    let currentIndent = getIndentLevel(line)

    if isKeyword(line) and (currentIndent <= indentLevel or not isCollecting):
      if isCollecting:
        if currentToken.range.lineEnd == -1:
          currentToken.range.lineEnd = i - 1
        tokens.add(currentToken)
        isCollecting = false

      # FIXME: after var, etc. there can be more than one space. Need to handle that.
      # TODO: remove some boilerplate code, const, enum, vars are very similar
      # FIXME: a var/const/enum/etc. does not necessarily have an =, it can also have :
      # TODO: there can be an annotation above a var
      if trimmedLine.startsWith("func "):
        isCollecting = true
        indentLevel = currentIndent
        currentToken = Token(
          tokenType: TokenType.Function,
          name: trimmedLine.split("(")[0][5 ..^ 1],
          lines: @[line],
          range: Range(lineStart: i, lineEnd: -1),
        )
      elif trimmedLine.startsWith("var "):
        let parts = trimmedLine.split("=")
        let varName = parts[0].strip().split(" ", 2)[1]
        tokens.add(
          Token(
            tokenType: TokenType.Variable,
            name: varName,
            lines: @[line],
            range: Range(lineStart: i, lineEnd: i),
          )
        )
      elif trimmedLine.startsWith("const "):
        let parts = trimmedLine.split("=")
        let constName = parts[0].strip().split(" ", 2)[1]
        tokens.add(
          Token(
            tokenType: TokenType.Constant,
            name: constName,
            lines: @[line],
            range: Range(lineStart: i, lineEnd: i),
          )
        )
      elif trimmedLine.startsWith("signal "):
        let signalName = trimmedLine.split("(", 1)[0][7 ..^ 1]
        tokens.add(
          Token(
            tokenType: TokenType.Signal,
            name: signalName,
            lines: @[line],
            range: Range(lineStart: i, lineEnd: i),
          )
        )
      elif trimmedLine.startsWith("class "):
        isCollecting = true
        indentLevel = currentIndent
        currentToken = Token(
          tokenType: TokenType.Class,
          name: trimmedLine.split(" ", 2)[1],
          lines: @[line],
          range: Range(lineStart: i, lineEnd: -1),
        )
      elif trimmedLine.startsWith("enum "):
        isCollecting = true
        indentLevel = currentIndent
        currentToken = Token(
          tokenType: TokenType.Enum,
          name: trimmedLine.split(" ", 2)[1],
          lines: @[line],
          range: Range(lineStart: i, lineEnd: -1),
        )
    elif isCollecting:
      if currentIndent > indentLevel or trimmedLine == "":
        currentToken.lines.add(line)
      else:
        tokens.add(currentToken)
        isCollecting = false

    if i == lines.high and isCollecting:
      currentToken.range.lineEnd = i
      tokens.add(currentToken)

  # We collect lines naively, then we remove empty lines from the end of each token.
  var mutableTokens = tokens
  for token in mutableTokens.mitems():
    while token.lines.len > 0 and token.lines[^1].isEmptyOrWhitespace():
      token.lines.setLen(token.lines.len - 1)
  return mutableTokens

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
  # TODO: Fix multiline parsing for enums, variables...
  # TODO: Write down algorithm and simplify common cases
  let tokens = parseGDScript(testCode)
  for token in tokens:
    echo "Type: ", token.tokenType
    echo "Name: ", token.name
    echo "Range: ", token.range.lineStart, " - ", token.range.lineEnd
    echo "Content:"
    echo token.lines.join("\n")
    echo "---"
