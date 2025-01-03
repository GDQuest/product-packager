# TODO:
# - Parse attributes, strings, bools (name only or name=true), and JSX expressions
#

# REFERENCES:
  #
import parse_base_tokens
import shared

type
  AttributeValueType = enum
    StringLiteral
    Boolean
    JSXExpression

  AttributeValue* = ref object
    case kind*: AttributeValueType
    of StringLiteral:
      stringValue*: Range
    of Boolean:
      boolValue*: bool
    of JSXExpression:
      expressionRange*: Range
    else:
      discard

  InlineType* = enum
    MdxComponent
    #Link
    #Image
    #Bold
    #Italic

  InlineToken* = object
    case kind*: InlineType
    of MdxComponent:
      name*: Range
      isSelfClosing*: bool
      # This allows us to distinguish the opening tag and body for further parsing
      openingTagRange*: Range
      bodyRange*: Range
      # Whether the component is a react fragment (<></>) or not
      isFragment*: bool = false
      attributes*: seq[MdxAttribute]
      children*: seq[InlineToken]
    else:
      discard

proc scanImportExport*(s: TokenScanner): InlineToken =
  # TODO:
  # Reference: Import export syntax: https://github.com/micromark/micromark-extension-mdxjs-esm#syntax
  result = InlineToken(kind: MdxComponent, name: s.getCurrentToken().range)

proc inlineParseMdxComponent*(s: TokenScanner): InlineToken =
  ## Parses and returns an MDX component, its attributes, and children if applicable.
  ## The function assumes the scanner is at the start of the component.
  #
  # Parsing rules:
  #
  # - Attributes can be a single word, in that case it's a boolean flag. To find
  # these attributes we can look for a text token containing identifiers
  # separated by one or more spaces. So we have to look for those in every text token.
  # TODO: consider getting the mdx component opening tag range and scanning characters instead of tokens?
  #
  # TODO:
  # - Add support for nested components (parse MDX and code inside code fences etc.)
  # - test <></> syntax
  let start = s.current

  # Get component name. It has to start with an uppercase letter.
  var name: Range
  let firstToken = s.currentToken
  if firstToken.kind == Text:
    let checkRange = firstToken.stripTokenText(s.source, {' '})
    let firstChar = s.source[checkRange.start]
    if firstChar >= 'A' and firstChar <= 'Z':
      # Find end of component name (first non-alphanumeric/underscore character)
      var nameEnd = checkRange.start + 1
      while nameEnd < checkRange.end:
        let c = s.source[nameEnd]
        if not isAlphanumericOrUnderscore(c):
          break
        nameEnd += 1
      name = Range(start: firstToken.range.start, `end`: nameEnd)
      s.current += 1
    else:
      return nil
  else:
    if firstToken.kind == CloseAngle:
      s.current += 1

  # Look for end of opening tag or self-closing mark
  var wasClosingMarkFound = false
  var isSelfClosing = false
  while not s.isAtEnd():
    case s.currentToken.kind
    of Slash:
      if s.peek(1).kind == CloseAngle:
        isSelfClosing = true
        wasClosingMarkFound = true
        s.current += 2
        break
      else:
        s.current += 1
    of CloseAngle:
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
    let componentName: string = s.source[name.start ..< name.end]
    while not s.isAtEnd():
      if s.currentToken.kind == OpenAngle and s.peek().kind == Slash:
        bodyEnd = s.current
        s.current += 2
        let nameToken = s.currentToken
        if nameToken.kind == Text and
          let nameRange = nameToken.stripTokenText(s.source, {' '}):
          s.source[nameRange.start ..< nameRange.end] == componentName:
          s.current += 1
          if s.currentToken.kind == CloseAngle:
            s.current += 1
            break
        break
      s.current += 1

  if isSelfClosing:
    return InlineToken(
      kind: MdxComponent,
      isSelfClosing: true,
      range: Range(start: start, `end`: s.current),
      name: name,
    )
  else:
    return InlineToken(
      kind: MdxComponent,
      isSelfClosing: false,
      range: Range(start: start, `end`: s.current),
      name: name,
      openingTagRange: Range(start: start, `end`: openingTagEnd),
      bodyRange: Range(start: openingTagEnd, `end`: bodyEnd),
    )
