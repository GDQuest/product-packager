## Basic tokenizer for the MDX parser. Walks the document and separates text
## from special characters to make block-level and inline parsing more readable
## and avoid walking character by character in the following steps.
import shared

const SpecialChars = {
  '`', '{', '}', '[', ']', '#', '<', '>', '/', '*', '_', '=', '!', '(', ')', '"', '\'', ',', ';', '\n'
}

type
  LexerTokenType* = enum
    Backtick      # `
    OpenBrace     # {
    CloseBrace    # }
    OpenBracket   # [
    CloseBracket  # ]
    Hash          # #
    OpenAngle     # <
    CloseAngle    # >
    Slash         # /
    Asterisk      # *
    Underscore    # _
    Equals        # =
    Exclamation   # !
    OpenParen     # (
    CloseParen    # )
    DoubleQuote   # "
    SingleQuote   # '
    Comma         # ,
    Semicolon     # ;
    Text          # Any text or whitespace
    Newline       # \n
    EOF           # End of file marker

  LexerToken* = object
    kind*: LexerTokenType
    range*: Range

  TokenScanner* = ref object
    tokens*: seq[LexerToken]
    current*: int
    source*: string
    peekIndex*: int

proc tokenize*(source: string): seq[LexerToken] =
  var tokens: seq[LexerToken] = @[]
  var current = 0

  proc addToken(tokenType: LexerTokenType, start, ende: int) =
    tokens.add(LexerToken(
      kind: tokenType,
      range: Range(start: start, `end`: ende)
    ))

  while current < source.len:
    let start = current
    let c = source[current]

    case c
    of '`':
      addToken(Backtick, start, current + 1)
    of '{':
      addToken(OpenBrace, start, current + 1)
    of '}':
      addToken(CloseBrace, start, current + 1)
    of '[':
      addToken(OpenBracket, start, current + 1)
    of ']':
      addToken(CloseBracket, start, current + 1)
    of '<':
      addToken(OpenAngle, start, current + 1)
    of '>':
      addToken(CloseAngle, start, current + 1)
    of '/':
      addToken(Slash, start, current + 1)
    of '#':
      addToken(Hash, start, current + 1)
    of '*':
      addToken(Asterisk, start, current + 1)
    of '_':
      addToken(Underscore, start, current + 1)
    of '=':
      addToken(Equals, start, current + 1)
    of '!':
      addToken(Exclamation, start, current + 1)
    of '(':
      addToken(OpenParen, start, current + 1)
    of ')':
      addToken(CloseParen, start, current + 1)
    of '"':
      addToken(DoubleQuote, start, current + 1)
    of '\'':
      addToken(SingleQuote, start, current + 1)
    of ',':
      addToken(Comma, start, current + 1)
    of ';':
      addToken(Semicolon, start, current + 1)
    of '\n':
      addToken(Newline, start, current + 1)
    of '\0':
      addToken(EOF, start, current + 1)
    else:
      let textStart = current
      while current < source.len and not SpecialChars.contains(source[current]):
        current += 1

      let textRange = Range(start: textStart, `end`: current)
      if textRange.start != textRange.end:
        tokens.add(LexerToken(
          kind: Text,
          range: Range(start: textRange.start, `end`: textRange.end),
        ))
      continue
    current += 1
  return tokens

proc getString*(range: Range, source: string): string {.inline.} =
  return source[range.start..<range.end]

proc getCurrentToken*(s: TokenScanner): LexerToken {.inline.} =
  return s.tokens[s.current]

proc peek*(s: TokenScanner, offset: int = 0): LexerToken {.inline.} =
  s.peekIndex = s.current + offset
  if s.peekIndex >= s.tokens.len:
    return s.tokens[^1]
  return s.tokens[s.peekIndex]

proc matchToken*(s: TokenScanner, expected: LexerTokenType): bool {.inline.} =
  if s.getCurrentToken().kind != expected:
    return false
  s.current += 1
  return true

proc isAtEnd*(s: TokenScanner): bool {.inline.} =
  return s.current >= s.tokens.len

proc isAlphanumericOrUnderscore*(c: char): bool {.inline.} =
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit
