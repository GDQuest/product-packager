#TODO: Move definitions and functions to a separate file imported by the parser's different parts?
import parse_base_tokens

type
  InlineType* = enum
    MdxComponent
    #Link
    #Image
    #Bold
    #Italic

  InlineToken* = ref object
    range*: Range
    case kind*: InlineType
    of MdxComponent:
      name*: Range
      isSelfClosing*: bool
      # This allows us to distinguish the opening tag and body for further parsing
      openingTagRange*: Range
      bodyRange*: Range

proc inlineParseMdxComponent*(s: TokenScanner): InlineToken =
  # TODO:
  # - Add support for nested components (parse MDX and code inside code fences etc.)
  # - test <></> syntax
  # - consider case of parsing mdx with line returns within a markdown paragraph. E.g.
  # Bla bla <Component>
  # ...
  # </Component>
  # This is not supported by the MDX package.
  let start = s.current

  # Get component name. It has to start with an uppercase letter.
  var name: Range
  let firstToken = s.getCurrentToken()
  if firstToken.kind == Text:
    let firstChar = s.source[firstToken.range.start]
    if firstChar >= 'A' and firstChar <= 'Z':
      # Find end of component name (first non-alphanumeric/underscore character)
      var nameEnd = firstToken.range.start + 1
      while nameEnd < firstToken.range.end:
        let c = s.source[nameEnd]
        if not isAlphanumericOrUnderscore(c):
          break
        nameEnd += 1
      name = Range(start: firstToken.range.start, `end`: nameEnd)
      s.current += 1
    else:
      return nil
  else:
    return nil

  # Look for end of opening tag or self-closing mark
  var wasClosingMarkFound = false
  var isSelfClosing = false
  while not s.isAtEnd():
    let token = s.getCurrentToken()
    case token.kind:
      of Slash:
        let nextToken = s.peek(1)
        if nextToken.kind == CloseAngle:
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
      message: "Expected closing mark '>' or self-closing mark '/>'"
    )

  let openingTagEnd = s.current
  var bodyEnd = openingTagEnd

  # Find matching closing tag
  if not isSelfClosing:
    let componentName = s.source[name.start..<name.end]
    while not s.isAtEnd():
      if s.getCurrentToken().kind == OpenAngle and
          s.peek().kind == Slash:
        bodyEnd = s.current
        s.current += 2
        let nameToken = s.getCurrentToken()
        if nameToken.kind == Text and
            s.source[nameToken.range.start..<nameToken.range.end] == componentName:
          s.current += 1
          if s.getCurrentToken().kind == CloseAngle:
            s.current += 1
            break
        break
      s.current += 1

  if isSelfClosing:
    return InlineToken(
      kind: MdxComponent,
      isSelfClosing: true,
      range: Range(start: start, `end`: s.current),
      name: name
    )
  else:
    return InlineToken(
      kind: MdxComponent,
      isSelfClosing: false,
      range: Range(start: start, `end`: s.current),
      name: name,
      openingTagRange: Range(start: start, `end`: openingTagEnd),
      bodyRange: Range(start: openingTagEnd, `end`: bodyEnd)
    )
