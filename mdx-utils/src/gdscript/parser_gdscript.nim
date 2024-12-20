## Minimal GDScript parser specialized for code include shortcodes. Tokenizes
## symbol definitions and their body and collects all their content.
##
## Preprocesses GDScript code to extract code between anchor comments, like
## #ANCHOR:anchor_name
## ... Code here
## #END:anchor_name
##
## This works in 2 passes:
##
## 1. Preprocesses the code to extract the code between anchor comments and remove anchor comments.
## 2. Parses the preprocessed code to tokenize symbols and their content.
##
## Users can then query and retrieve the code between anchors or the definition
## and body of a symbol.
##
## This was originally written as a tool to only parse GDScript symbols, with
## the anchor preprocessing added later, so the approach may not be the most
## efficient.
import std/[tables, unittest, strutils, times]
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
    source: string
    current: int
    indentLevel: int
    bracketDepth: int
    peekIndex: int

  CodeAnchor = object
    ## A code anchor is how we call comments used to mark a region in the code, with the form
    ## #ANCHOR:anchor_name
    ## ...
    ## #END:anchor_name
    ##
    ## This object is used to extract the code between the anchor and the end tag.
    nameStart, nameEnd: int
    codeStart, codeEnd: int
    # Used to remove the anchor tags from the final code
    # codeStart marks the end of the anchor tag, codeEnd marks the start of the end tag
    anchorTagStart, endTagEnd: int

  GDScriptFile = object
    ## Represents a parsed GDScript file with its symbols and source code
    filePath: string
    source: string
    ## Map of symbol names to their tokens
    symbols: Table[string, Token]
    ## Map of anchor names to their code anchors
    anchors: Table[string, CodeAnchor]

  SymbolQuery = object
    ## Represents a query to get a symbol from a GDScript file, like
    ## ClassName.definition or func_name.body or var_name.
    name: string
    isDefinition: bool
    isBody: bool
    isClass: bool
    childName: string

# Caches parsed GDScript files
var gdscriptFiles = initTable[string, GDScriptFile]()

proc getCode(token: Token, source: string): string {.inline.} =
  return source[token.range.start ..< token.range.end]

proc getName(token: Token, source: string): string {.inline.} =
  return source[token.nameStart ..< token.nameEnd]

proc getDefinition(token: Token, source: string): string {.inline.} =
  return source[token.range.definitionStart ..< token.range.definitionEnd]

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

proc printTokens(tokens: seq[Token], source: string) =
  echo "Parsed Tokens:"
  for token in tokens:
    printToken(token, source)
    echo ""

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
  for i in 0 ..< length:
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

proc countIndentationAndAdvance(s: var Scanner): int {.inline.} =
  ## Counts the number of spaces and tabs starting from the current position
  ## Advances the scanner as it counts the indentation
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
    case c
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
  ## Scans to the end of the current line, returning the start (the current
  ## position when the function was called) and end positions (the \n character
  ## at the end of the line).
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
  result =
    s.peekString("func") or s.peekString("var") or s.peekString("const") or
    s.peekString("class") or s.peekString("signal") or s.peekString("enum") or
    # TODO: Consider how to handle regular comments vs anchors
    s.peekString("#ANCHOR") or s.peekString("#END") or s.peekString("# ANCHOR") or
    s.peekString("# END")
  s.current = savedPos
  return result

proc scanBody(s: var Scanner, startIndent: int): tuple[bodyStart, bodyEnd: int] =
  let start = s.current
  while not s.isAtEnd():
    let currentIndent = s.countIndentationAndAdvance()
    if currentIndent <= startIndent and not s.isAtEnd():
      if isNewDefinition(s):
        break

    discard scanToEndOfLine(s)
  # s.current points to the first letter of the next token, after the
  # indentation. We need to backtrack to find the actual end of the body.
  var index = s.current - 1
  while index > 0 and s.source[index] in [' ', '\r', '\t', '\n']:
    index -= 1
  s.current = index + 1
  result = (start, s.current)

proc scanAnchorToken(s: var Scanner, startPos: int): CodeAnchor =
  ## Scans from a #ANCHOR tag to the matching #END tag
  ## This is used in a preprocessing pass.

  result.anchorTagStart = startPos

  # Skip the #ANCHOR: or # ANCHOR: part
  while s.getCurrentChar() != ':':
    s.current += 1
  s.skipWhitespace()
  # Skip the colon to parse the anchor name
  s.current += 1

  let (nameStart, nameEnd) = s.scanIdentifier()
  discard s.scanToEndOfLine()

  result.nameStart = nameStart
  result.nameEnd = nameEnd
  result.codeStart = s.current

  # Look for the matching END tag
  let anchorName = s.source[nameStart ..< nameEnd]
  var foundEndTag = false

  let endTag = "#END:" & anchorName
  let endTagWithSpace = "# END:" & anchorName
  while not s.isAtEnd():
    s.skipWhitespace()
    if s.peekString(endTag) or s.peekString(endTagWithSpace):
      foundEndTag = true
      result.codeEnd = s.current
      discard s.scanToEndOfLine()
      result.endTagEnd = s.current
      break

    if not s.isAtEnd():
      discard s.advance()

  if not foundEndTag:
    # The anchor is not closed, reset the scanner to after the anchor's opening
    # tag, raise an error, and allow continuing with parsing.
    s.current = result.codeStart
    raise newException(
      ValueError, "Anchor region " & anchorName & " is missing an #END tag."
    )

proc scanToken(s: var Scanner): Token =
  while not s.isAtEnd():
    s.indentLevel = s.countIndentationAndAdvance()
    s.skipWhitespace()

    let startPos = s.current
    let c = s.getCurrentChar()
    case c
    # Comment, skip to end of line and continue
    of '#':
      discard s.scanToEndOfLine()
      continue
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
      discard

    s.current += 1

  return Token(tokenType: TokenType.Invalid)

proc parseClass(s: var Scanner, classToken: var Token) =
  ## Parses the body of a class, collecting child tokens
  let classIndent = s.indentLevel
  s.current = classToken.range.bodyStart
  while not s.isAtEnd():
    #Problem: s is on the first char of the token instead of the beginning of the line
    let currentIndent = s.countIndentationAndAdvance()
    if currentIndent <= classIndent:
      if isNewDefinition(s):
        break

    let childToken = s.scanToken()
    if childToken.tokenType != TokenType.Invalid:
      classToken.children.add(childToken)

proc parseGDScript(source: string): seq[Token] =
  var scanner =
    Scanner(source: source, current: 0, indentLevel: 0, bracketDepth: 0, peekIndex: 0)
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

proc parseGDScriptFile(path: string) =
  # Parses a GDScript file and caches it
  let source = readFile(path)
  let tokens = parseGDScript(source)
  var symbols = initTable[string, Token]()
  for token in tokens:
    let name = token.getName(source)
    symbols[name] = token

  gdscriptFiles[path] = GDScriptFile(filePath: path, source: source, symbols: symbols)

proc getTokenFromCache(symbolName: string, filePath: string): Token =
  # Gets a token from the cache given a symbol name and the path to the GDScript file
  if not gdscriptFiles.hasKey(filePath):
    echo "Token not found, " & filePath & " not in cache. Parsing file..."
    parseGDScriptFile(filePath)

  let file = gdscriptFiles[filePath]
  if not file.symbols.hasKey(symbolName):
    raise newException(
      ValueError, "Symbol not found: '" & symbolName & "' in file: '" & filePath & "'"
    )

  return file.symbols[symbolName]

proc getSymbolText(symbolName: string, path: string): string =
  # Gets the text of a symbol given its name and the path to the file
  let token = getTokenFromCache(symbolName, path)
  let file = gdscriptFiles[path]
  return token.getCode(file.source)

proc getSymbolDefinition(symbolName: string, path: string): string =
  # Gets the definition of a symbol given its name and the path to the file
  let token = getTokenFromCache(symbolName, path)
  let file = gdscriptFiles[path]
  return token.getDefinition(file.source)

proc getSymbolBody(symbolName: string, path: string): string =
  # Gets the body of a symbol given its name and the path to the file: it excludes the definition
  let token = getTokenFromCache(symbolName, path)
  if token.tokenType notin [TokenType.Class, TokenType.Function]:
    raise newException(
      ValueError,
      "Symbol '" & symbolName & "' is not a class or function in file: '" & path &
        "'. Cannot get body: only functions and classes have a body.",
    )
  let file = gdscriptFiles[path]
  return token.getBody(file.source)

proc parseSymbolQuery(query: string): SymbolQuery =
  ## Turns a symbol query string like ClassName.body or ClassName.function.definition
  ## into a SymbolQuery object for easier processing.
  let parts = query.split('.')

  result.name = parts[0]
  if parts.len == 2:
    if parts[1] in ["definition", "def"]:
      result.isDefinition = true
    elif parts[1] == "body":
      result.isBody = true
    else:
      result.childName = parts[1]
      result.isClass = true
  elif parts.len == 3:
    if parts[2] in ["definition", "def"]:
      result.childName = parts[1]
      result.isClass = true
      result.isDefinition = true
    elif parts[2] == "body":
      result.childName = parts[1]
      result.isClass = true
      result.isBody = true
    else:
      raise newException(ValueError, "Invalid symbol query: '" & query & "'")

proc getCode*(symbolQuery: string, filePath: string): string =
  ## Gets the code of a symbol given a query and the path to the file
  ## The query can be:
  ## - A symbol name like a function or class name
  ## - The path to a symbol, like ClassName.functionName
  ## - The request of a definition, like functionName.definition
  ## - The request of a body, like functionName.body
  let query = parseSymbolQuery(symbolQuery)
  if query.isClass:
    let classToken = getTokenFromCache(query.name, filePath)
    let file = gdscriptFiles[filePath]

    for child in classToken.children:
      if child.getName(file.source) == query.childName:
        if query.isDefinition:
          result = child.getDefinition(file.source)
        elif query.isBody:
          result = child.getBody(file.source)
        else:
          result = child.getCode(file.source)
    raise newException(
      ValueError,
      "Symbol not found: '" & query.childName & "' in class '" & query.name & "'",
    )
  elif query.isDefinition:
    result = getSymbolDefinition(query.name, filePath)
  elif query.isBody:
    result = getSymbolBody(query.name, filePath)
  else:
    result = getSymbolText(query.name, filePath)

proc runPerformanceTest() =
  let codeTest =
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

  echo "Running performance test..."
  var totalDuration = 0.0
  for i in 0 ..< 10:
    let start = cpuTime()
    for j in 0 ..< 10000:
      discard parseGDScript(codeTest)
    let duration = (cpuTime() - start) * 1000
    totalDuration += duration

  let averageDuration = totalDuration / 10
  echo "Average parse duration for 10 000 calls: ",
    averageDuration.formatFloat(ffDecimal, 3), "ms"

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
          tokens[0].getName(code) == "_ready"
          tokens[1].tokenType == TokenType.Function
          tokens[1].getName(code) == "deactivate"

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

    test "Parse larger inner class with anchors":
      let code =
        """
#ANCHOR:class_StateDie
class StateDie extends State:

	const SmokeExplosionScene = preload("res://assets/vfx/smoke_vfx/smoke_explosion.tscn")

	func _init(init_mob: Mob3D) -> void:
		super("Die", init_mob)

	func enter() -> void:
		mob.skin.play("die")

		var smoke_explosion := SmokeExplosionScene.instantiate()
		mob.add_sibling(smoke_explosion)
		smoke_explosion.global_position = mob.global_position

		mob.skin.animation_finished.connect(func (_animation_name: String) -> void:
			mob.queue_free()
		)
#END:class_StateDie
"""
      let tokens = parseGDScript(code)
      echo tokens[0].getCode(code)
      check:
        tokens.len == 1
      if tokens.len == 1:
        let classToken = tokens[0]
        check:
          classToken.tokenType == TokenType.Class
          classToken.getName(code) == "StateDie"
          classToken.children.len == 3
          # Trailing anchor comments should not be included in the token
          not classToken.getBody(code).contains("#END")
      else:
        echo "Found tokens: ", tokens.len
        printTokens(tokens, code)

when isMainModule:
  runUnitTests()
  #runPerformanceTest()
