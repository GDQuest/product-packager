## Minimal GDScript parser for code include shortcodes. Tokenizes functions, variables, and signals and collects all their content.
import std/[strutils, times]

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
  for i, line in lines:
    let trimmedLine = line.strip()
    let currentIndent = getIndentLevel(line)

    if isKeyword(line) and (currentIndent <= indentLevel or not isCollecting):
      if isCollecting:
        if currentToken.range.lineEnd == -1:
          currentToken.range.lineEnd = i - 1
        tokens.add(currentToken)
        isCollecting = false

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
        let varName = parts[0].strip().split(" ")[1]
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
        let constName = parts[0].strip().split(" ")[1]
        tokens.add(
          Token(
            tokenType: TokenType.Constant,
            name: constName,
            lines: @[line],
            range: Range(lineStart: i, lineEnd: i),
          )
        )
      elif trimmedLine.startsWith("signal "):
        let signalName = trimmedLine.split("(")[0][7 ..^ 1]
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
          name: trimmedLine.split(" ")[1],
          lines: @[line],
          range: Range(lineStart: i, lineEnd: -1),
        )
      elif trimmedLine.startsWith("enum "):
        isCollecting = true
        indentLevel = currentIndent
        currentToken = Token(
          tokenType: TokenType.Enum,
          name: trimmedLine.split(" ")[1],
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
  # TODO: Fix multiline parsing for enums, variables...
  # TODO: Remove empty lines after a token
  let tokens = parseGDScript(testCode)
  for token in tokens:
    echo "Type: ", token.tokenType
    echo "Name: ", token.name
    echo "Range: ", token.range.lineStart, " - ", token.range.lineEnd
    echo "Content:"
    echo token.lines.join("\n")
    echo "---"
