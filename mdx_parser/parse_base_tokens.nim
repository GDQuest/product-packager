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

  Token*[T] = object
    kind*: T
    range*: Range

  LexerToken* = Token[LexerTokenType]

  Scanner*[T] = ref object of RootObj
    tokens*: seq[T]
    current*: int
    source*: string
    peekIndex*: int

  TokenScanner* = ref object of Scanner[LexerToken]

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

proc getString*(range: Range, source: string): string {.inline.} =
  return source[range.start ..< range.end]

proc currentToken*(s: Scanner): LexerToken {.inline.} =
  return s.tokens[s.current]

proc peek*(s: Scanner, offset: int = 0): LexerToken {.inline.} =
  s.peekIndex = s.current + offset
  if s.peekIndex >= s.tokens.len:
    return s.tokens[^1]
  return s.tokens[s.peekIndex]

proc isPeekSequence*(s: Scanner, sequence: seq[LexerTokenType]): bool {.inline.} =
  ## Returns `true` if the next tokens in the scanner match the given sequence.
  for i, tokenType in sequence:
    if s.peek(i).kind != tokenType:
      return false
  return true

proc matchToken*(s: Scanner, expected: LexerTokenType): bool {.inline.} =
  if s.currentToken.kind != expected:
    return false
  s.current += 1
  return true

proc isAtEnd*(s: Scanner): bool {.inline.} =
  return s.current >= s.tokens.len

proc isAlphanumericOrUnderscore*(c: char): bool {.inline.} =
  let isLetter = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
  let isDigit = c >= '0' and c <= '9'
  return isLetter or isDigit

proc advanceToNewline*(s: Scanner) {.inline.} =
  ## Advances until the next newline character or the end of the tokens.
  ## Stops at a Newline token.
  while not s.isAtEnd() and s.currentToken.kind != Newline:
    s.current += 1

proc advanceToNextLineStart*(s: Scanner) {.inline.} =
  ## Advances to the first token of the next line, or the end of the tokens.
  s.advanceToNewline()
  if not s.isAtEnd():
    s.current += 1
