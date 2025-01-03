## Basic tokenizer for the MDX parser. Walks the document and separates text
## from special characters to make block-level and inline parsing more readable
## and avoid walking character by character in the following steps.
##
## TODO: question: should we tokenize things like </ or < / as "closing
## component start" etc. directly in this pass?
import shared

## Set of characters that we want to tokenize separately.
const SpecialChars = {
  '`', '{', '}', '[', ']', '#', '<', '>', '/', '*', '_', '=', '!', '(', ')', '"', '\'',
  ',', ';', '\n', '-',
}

type
  LexerTokenType* = enum
    Backtick # `
    OpenBrace # {
    CloseBrace # }
    OpenBracket # [
    CloseBracket # ]
    Hash # #
    OpenAngle # <
    CloseAngle # >
    Slash # /
    Asterisk # *
    Underscore # _
    Equals # =
    Exclamation # !
    OpenParen # (
    CloseParen # )
    DoubleQuote # "
    SingleQuote # '
    Comma # ,
    Semicolon # ;
    Dash # -
    Text # Any text or whitespace but not \n
    Newline # \n
    EOF # End of file marker

  LexerToken* = object
    kind*: LexerTokenType
    range*: Range

type LexerScanner* = Scanner[LexerToken]

proc isPeekSequence*(s: LexerScanner, sequence: seq[LexerTokenType]): bool {.inline.} =
  for i, tokenType in sequence:
    if s.peek(i).kind != tokenType:
      return false
  return true

proc matchToken*(s: LexerScanner, expected: LexerTokenType): bool {.inline.} =
  if s.currentToken.kind != expected:
    return false
  s.current += 1
  return true

proc advanceToNewline*(s: LexerScanner) {.inline.} =
  while not s.isAtEnd() and s.currentToken.kind != Newline:
    s.current += 1

proc advanceToNextLineStart*(s: LexerScanner) {.inline.} =
  s.advanceToNewline()
  if not s.isAtEnd():
    s.current += 1

proc tokenize*(source: string): seq[LexerToken] =
  var tokens: seq[LexerToken] = @[]
  var current = 0

  proc addToken(tokenType: LexerTokenType, start, ende: int) =
    tokens.add(LexerToken(kind: tokenType, range: Range(start: start, `end`: ende)))

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
    of '-':
      addToken(Dash, start, current + 1)
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
        tokens.add(
          LexerToken(
            kind: Text, range: Range(start: textRange.start, `end`: textRange.end)
          )
        )
      continue
    current += 1
  return tokens
