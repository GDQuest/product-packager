// Minimal GDScript parser specialized for code include shortcodes. Tokenizes
// symbol definitions and their body and collects all their content.
//
// Preprocesses GDScript code to extract code between anchor comments, like
// #ANCHOR:anchor_name
// ... Code here
// #END:anchor_name
//
// This works in 2 passes:
//
// 1. Preprocesses the code to extract the code between anchor comments and
// remove anchor comments. This produces a preprocessed source without anchors.
// 2. Parses the preprocessed code to tokenize symbols and their content.
//
// Users can then query and retrieve the code between anchors or the definition
// and body of a symbol.
//
// Note: This could be made more efficient by combining both passes into one,
// but the implementation evolved towards this approach and refactoring would
// only take time and potentially introduce regressions at this point.
//
// To combine passes into one, I would tokenize keywords, identifiers, anchor comments,
// brackets, and something generic like statement lines in one pass, then analyse
// and group the result.
import { assertEquals, assert } from "https://deno.land/std/testing/asserts.ts";

// TODO: replace with error logging module
const addError = (message: string, filepath: string = "") => {
  throw new Error(`Error in file ${filepath}: ${message}`);
};

enum TokenType {
  Invalid,
  Function,
  Variable,
  Constant,
  Signal,
  Class,
  ClassName,
  Enum,
}

interface TokenRange {
  // Start and end character positions of the entire token (definition + body if applicable) in the source code
  start: number;
  end: number;
  definitionStart: number;
  definitionEnd: number;
  bodyStart: number;
  bodyEnd: number;
}

interface Token {
  tokenType: TokenType;
  nameStart: number;
  nameEnd: number;
  range: TokenRange;
  children: Token[];
}

interface Scanner {
  source: string;
  current: number;
  indentLevel: number;
  bracketDepth: number;
  peekIndex: number;
}

interface AnchorTag {
  // Represents a code anchor tag, either a start or end tag,
  // like #ANCHOR:anchor_name or #END:anchor_name
  isStart: boolean;
  name: string;
  startPosition: number;
  endPosition: number;
}

interface CodeAnchor {
  // A code anchor is how we call comments used to mark a region in the code, with the form
  // #ANCHOR:anchor_name
  // ...
  // #END:anchor_name
  //
  // This object is used to extract the code between the anchor and the end tag.
  nameStart: number;
  nameEnd: number;
  codeStart: number;
  codeEnd: number;
  // Used to remove the anchor tags from the final code
  // codeStart marks the end of the anchor tag, codeEnd marks the start of the end tag
  anchorTagStart: number;
  endTagEnd: number;
}

interface GDScriptFile {
  // Represents a parsed GDScript file with its symbols and source code.
  filePath: string;
  // Full path to the GDScript file. Used to look up the parsed file in a
  // cache to avoid parsing multiple times.
  source: string;
  // Original source code, with anchor comments included.
  symbols: Map<string, Token>;
  // Map of symbol names to their tokens.
  anchors: Map<string, CodeAnchor>;
  // Map of anchor names to their code anchors.
  processedSource: string; // The source code with anchor tags removed.
}

interface SymbolQuery {
  // Represents a query to get a symbol from a GDScript file, like
  // ClassName.definition or func_name.body or var_name.
  name: string;
  isDefinition: boolean;
  isBody: boolean;
  isClass: boolean;
  childName: string;
}

// Caches parsed GDScript files
const gdscriptFiles = new Map<string, GDScriptFile>();

const printToken = (token: Token, source: string, indent = 0): void => {
  const indentStr = "  ".repeat(indent);
  console.log(`${indentStr}Token: ${TokenType[token.tokenType]}`);
  console.log(`${indentStr}  Name: ${getName(token, source)}`);
  console.log(`${indentStr}  Range:`);
  console.log(`${indentStr}    Start: ${token.range.start}`);
  console.log(`${indentStr}    End: ${token.range.end}`);

  if (token.children.length > 0) {
    console.log(`${indentStr}  Children:`);
    for (const child of token.children) {
      printToken(child, source, indent + 2);
    }
  }
};

const printTokens = (tokens: Token[], source: string): void => {
  console.log("Parsed Tokens:");
  for (const token of tokens) {
    printToken(token, source);
    console.log("");
  }
};

const charMakeWhitespaceVisible = (c: string): string => {
  // Replaces whitespace characters with visible equivalents.
  switch (c) {
    case "\t":
      return "⇥";
    case "\n":
      return "↲";
    case " ":
      return "·";
    default:
      return c;
  }
};

const getCurrentChar = (s: Scanner): string => {
  // Returns the current character without advancing the scanner's current index
  return s.source[s.current];
};

const getCurrentLine = (s: Scanner): string => {
  // Helper function to get the current line from the scanner's source without moving the current index.
  // Use this for debugging error messages and to get context about the current position in the source code.
  // Backtrack to start of line
  let start = s.current;
  while (start > 0 && s.source[start - 1] !== "\n") {
    start--;
  }

  // Find end of line
  let endPos = start;
  while (endPos < s.source.length && s.source[endPos] !== "\n") {
    endPos++;
  }

  return s.source.substring(start, endPos);
};

const advance = (s: Scanner): string => {
  // Reads and returns the current character, then advances the scanner by one
  const result = s.source[s.current];
  s.current++;
  return result;
};

const isAtEnd = (s: Scanner): boolean => {
  return s.current >= s.source.length;
};

const peekAt = (s: Scanner, offset: number): string => {
  // Peeks at a specific offset and returns the character without advancing the scanner
  s.peekIndex = s.current + offset;
  if (s.peekIndex >= s.source.length) {
    return "\0";
  }
  return s.source[s.peekIndex];
};

const peekString = (s: Scanner, expected: string): boolean => {
  // Peeks ahead to check if the expected string is present without advancing
  // Returns true if the string is found, false otherwise
  const length = expected.length;
  for (let i = 0; i < length; i++) {
    if (peekAt(s, i) !== expected[i]) {
      return false;
    }
  }
  s.peekIndex = s.current + length;
  return true;
};

const advanceToPeek = (s: Scanner): void => {
  // Advances the scanner to the stored getCurrentChar index
  s.current = s.peekIndex;
};

const matchString = (s: Scanner, expected: string): boolean => {
  // Returns true and advances the scanner if and only if the next characters match the expected string
  if (peekString(s, expected)) {
    advanceToPeek(s);
    return true;
  }
  return false;
};

const countIndentationAndAdvance = (s: Scanner): number => {
  // Counts the number of spaces and tabs starting from the current position
  // Advances the scanner as it counts the indentation
  // Call this function at the start of a line to count the indentation
  let result = 0;
  while (!isAtEnd(s)) {
    console.debug(`Current index: ${s.current}`);
    console.debug(
      `Current char is: ${charMakeWhitespaceVisible(getCurrentChar(s))}`,
    );
    const currentChar = getCurrentChar(s);
    if (currentChar === "\t") {
      result++;
      s.current++;
    } else if (currentChar === " ") {
      let spaces = 0;
      while (!isAtEnd(s) && getCurrentChar(s) === " ") {
        spaces++;
        s.current++;
      }
      result += Math.floor(spaces / 4);
      break;
    } else {
      break;
    }
  }
  console.debug(`Indentation: ${result}`);
  return result;
};

const skipWhitespace = (s: Scanner): void => {
  // Peeks at the next characters and advances the scanner until a non-whitespace character is found
  while (!isAtEnd(s)) {
    const c = getCurrentChar(s);
    if (c === " " || c === "\r" || c === "\t") {
      s.current++;
    } else {
      break;
    }
  }
};

const isAlphanumericOrUnderscore = (c: string): boolean => {
  // Returns true if the character is a letter, digit, or underscore
  const isLetter = (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") ||
    c === "_";
  const isDigit = c >= "0" && c <= "9";
  return isLetter || isDigit;
};

const scanIdentifier = (s: Scanner): { start: number; end: number } => {
  const start = s.current;
  while (!isAtEnd(s) && isAlphanumericOrUnderscore(getCurrentChar(s))) {
    advance(s);
  }
  return { start, end: s.current };
};

const scanToStartOfNextLine = (s: Scanner): { start: number; end: number } => {
  // Scans and advances to the first character of the next line.
  //
  // Returns an object with:
  // - start: The current position at the start of the function call
  // - end: The position of the first character of the next line
  if (isAtEnd(s)) {
    return { start: s.current, end: s.current };
  }

  const start = s.current;
  const length = s.source.length;
  let offset = 0;
  let c = s.source[s.current];
  while (c !== "\n") {
    offset++;
    if (s.current + offset >= length) {
      break;
    }
    c = s.source[s.current + offset];
  }
  s.current += offset;
  if (s.current < length) {
    s.current++;
  }
  return { start, end: s.current };
};

const scanToEndOfDefinition = (
  s: Scanner,
): { scanStart: number; definitionEnd: number } => {
  // Scans until the end of the line or until reaching the end of bracket pairs.
  const scanStart = s.current;
  while (!isAtEnd(s)) {
    const c = getCurrentChar(s);
    switch (c) {
      case "(":
      case "[":
      case "{":
        s.bracketDepth++;
        break;
      case ")":
      case "]":
      case "}":
        s.bracketDepth--;
        break;
      case "\n":
        if (s.bracketDepth === 0) {
          return { scanStart, definitionEnd: s.current };
        }
        break;
    }
    s.current++;
  }
  return { scanStart, definitionEnd: s.current };
};

const isAtStartOfDefinition = (s: Scanner): boolean => {
  // Returns true if there's a new definition ahead, regardless of its indent level
  // or type
  const savedPos = s.current;
  skipWhitespace(s);
  const result = peekString(s, "func") || peekString(s, "var") ||
    peekString(s, "const") ||
    peekString(s, "class") || peekString(s, "signal") ||
    peekString(s, "enum") ||
    // TODO: Consider how to handle regular comments vs anchors
    peekString(s, "#ANCHOR") || peekString(s, "#END") ||
    peekString(s, "# ANCHOR") ||
    peekString(s, "# END");
  s.current = savedPos;
  return result;
};

const scanBody = (
  s: Scanner,
  startIndent: number,
): { bodyStart: number; bodyEnd: number } => {
  // Scans the body of a function or class, starting from the current position
  // (assumed to be the start of the body).
  //
  // To detect the body, we store the end of the last line of code that belongs
  // to the body and scan until the next definition.
  let bodyStart = s.current;
  let bodyEnd = s.current;
  while (!isAtEnd(s)) {
    const currentIndent = countIndentationAndAdvance(s);
    if (currentIndent <= startIndent && !isAtEnd(s)) {
      if (isAtStartOfDefinition(s)) {
        break;
      }
    }

    if (currentIndent > startIndent) {
      scanToStartOfNextLine(s);
      bodyEnd = s.current;
      if (!isAtEnd(s)) {
        bodyEnd--;
      }
    } else {
      scanToStartOfNextLine(s);
    }
  }
  return { bodyStart, bodyEnd };
};

const scanAnchorTags = (s: Scanner): AnchorTag[] => {
  // Scans the entire file and collects all anchor tags (both start and end)
  // Returns them in the order they appear in the source code
  const result: AnchorTag[] = [];

  while (!isAtEnd(s)) {
    if (getCurrentChar(s) === "#") {
      const startPosition = s.current;

      // Look for an anchor, if not found skip to the next line. An anchor has
      // to take a line on its own.
      s.current++;
      skipWhitespace(s);

      const isAnchor = peekString(s, "ANCHOR");
      const isEnd = peekString(s, "END");

      if (!(isAnchor || isEnd)) {
        scanToStartOfNextLine(s);
        continue;
      } else {
        const tag: AnchorTag = {
          isStart: isAnchor,
          name: "",
          startPosition,
          endPosition: 0,
        };
        advanceToPeek(s);
        console.debug(
          `Found tag: ${s.source.substring(startPosition, s.current)}`,
        );

        // Jump to after the colon (:) to find the tag's name
        while (getCurrentChar(s) !== ":") {
          s.current++;
        }
        skipWhitespace(s);
        s.current++;
        skipWhitespace(s);

        const { start: nameStart, end: nameEnd } = scanIdentifier(s);
        tag.name = s.source.substring(nameStart, nameEnd);

        const { end: lineEnd } = scanToStartOfNextLine(s);
        tag.endPosition = lineEnd;

        result.push(tag);

        // If the current char isn't a line return, backtrack s.current to the line return
        while (!isAtEnd(s) && getCurrentChar(s) !== "\n") {
          s.current--;
        }
      }
    }
    s.current++;
  }
  console.debug(`Found ${result.length} anchor tags`);
  return result;
};

const preprocessAnchors = (source: string): {
  anchors: Map<string, CodeAnchor>;
  processed: string;
} => {
  // This function scans the source code for anchor tags and looks for matching opening and closing tags.
  // Anchor tags are comments used to mark a region in the code, with the form:
  //
  // #ANCHOR:anchor_name
  // ...
  // #END:anchor_name
  //
  // The function returns:
  //
  // 1. a Map of anchor region names mapped to CodeAnchor
  // objects, each representing a region of code between an anchor and its
  // matching end tag.
  // 2. A string with the source code with the anchor comment lines removed, to
  // parse symbols more easily in a separate pass.

  const s: Scanner = {
    source,
    current: 0,
    indentLevel: 0,
    bracketDepth: 0,
    peekIndex: 0,
  };

  // Anchor regions can be nested or intertwined, so we first scan all tags, then match opening and closing tags by name to build CodeAnchor objects
  const tags = scanAnchorTags(s);

  // Turn tags into maps to find matching pairs and check for duplicate names
  const startTags = new Map<string, AnchorTag>();
  const endTags = new Map<string, AnchorTag>();

  // TODO: add processed filename/path in errors
  for (const tag of tags) {
    if (tag.isStart) {
      if (startTags.has(tag.name)) {
        addError(`Duplicate ANCHOR tag found for: ${tag.name}`);
        return { anchors: new Map(), processed: "" };
      }
      startTags.set(tag.name, tag);
    } else {
      if (endTags.has(tag.name)) {
        addError(`Duplicate END tag found for: ${tag.name}`);
        return { anchors: new Map(), processed: "" };
      }
      endTags.set(tag.name, tag);
    }
  }

  // Validate tag pairs and create CodeAnchor objects
  const anchors = new Map<string, CodeAnchor>();

  for (const [name, startTag] of startTags) {
    if (!endTags.has(name)) {
      addError(`Missing #END tag for anchor: ${name}`);
      return { anchors: new Map(), processed: "" };
    }
  }

  for (const [name, endTag] of endTags) {
    if (!startTags.has(name)) {
      addError(`Found #END tag without matching #ANCHOR for: ${name}`);
      return { anchors: new Map(), processed: "" };
    }
  }

  for (const [name, startTag] of startTags) {
    const endTag = endTags.get(name)!;
    const anchor: CodeAnchor = {
      nameStart: startTag.startPosition,
      nameEnd: startTag.startPosition + name.length,
      anchorTagStart: startTag.startPosition,
      codeStart: startTag.endPosition,
      codeEnd: (() => {
        let codeEndPos = endTag.startPosition;
        while (source[codeEndPos] !== "\n") {
          codeEndPos--;
        }
        return codeEndPos;
      })(),
      endTagEnd: endTag.endPosition,
    };

    anchors.set(name, anchor);
  }

  // Preprocess source code by removing anchor tag lines
  let processedSource = "";
  let lastEnd = 0;

  for (const tag of tags) {
    // Tags can be indented, so we backtrack to the start of the line to strip
    // the entire line of code containing the tag
    let tagLineStart = tag.startPosition;
    while (tagLineStart > 0 && source[tagLineStart - 1] !== "\n") {
      tagLineStart--;
    }
    processedSource += source.substring(lastEnd, tagLineStart);
    lastEnd = tag.endPosition;
  }
  processedSource += source.substring(lastEnd);

  // Trim trailing whitespace but preserve leading whitespace
  return {
    anchors,
    processed: processedSource.replace(/\s+$/, ""),
  };
};

const scanNextToken = (s: Scanner): Token => {
  // Finds and scans the next token in the source code and returns a Token object.
  while (!isAtEnd(s)) {
    console.debug(`At top of loop. Current index: ${s.current}`);
    s.indentLevel = countIndentationAndAdvance(s);
    console.debug(`Indent level: ${s.indentLevel}`);
    skipWhitespace(s);
    console.debug(`After whitespace. Current index: ${s.current}`);

    if (isAtEnd(s)) {
      break;
    }

    const startPos = s.current;
    const c = getCurrentChar(s);
    console.debug(`Current char: ${charMakeWhitespaceVisible(c)}`);

    switch (c) {
      // Comment, skip to the next line
      case "#": {
        scanToStartOfNextLine(s);
        continue;
      }
      // Function definition
      case "f": {
        if (matchString(s, "func")) {
          const token: Token = {
            tokenType: TokenType.Function,
            nameStart: 0,
            nameEnd: 0,
            range: {
              start: startPos,
              end: 0,
              definitionStart: startPos,
              definitionEnd: 0,
              bodyStart: 0,
              bodyEnd: 0,
            },
            children: [],
          };

          skipWhitespace(s);
          const { start: nameStart, end: nameEnd } = scanIdentifier(s);
          token.nameStart = nameStart;
          token.nameEnd = nameEnd;

          while (getCurrentChar(s) !== ":") {
            s.current++;
          }
          scanToStartOfNextLine(s);

          token.range.definitionEnd = s.current;
          token.range.bodyStart = s.current;

          const { bodyStart, bodyEnd } = scanBody(s, s.indentLevel);
          token.range.bodyEnd = bodyEnd;
          token.range.end = bodyEnd;

          return token;
        }
        break;
      }
      // Annotation
      case "@": {
        let offset = 1;
        let c2 = peekAt(s, offset);
        while (c2 !== "\n") {
          offset++;
          c2 = peekAt(s, offset);
          if (c2 === "\n") {
            // This is an annotation on a single line, we skip this for now.
            advanceToPeek(s);
          } else if (c2 === "v") {
            // Check if this is a variable definition, if so, create a var token,
            // and include the inline annotation in the definition
            advanceToPeek(s);
            offset = 0;
            if (matchString(s, "var")) {
              const token: Token = {
                tokenType: TokenType.Variable,
                nameStart: 0,
                nameEnd: 0,
                range: {
                  start: startPos,
                  end: 0,
                  definitionStart: startPos,
                  definitionEnd: 0,
                  bodyStart: 0,
                  bodyEnd: 0,
                },
                children: [],
              };

              skipWhitespace(s);

              const { start: nameStart, end: nameEnd } = scanIdentifier(s);
              token.nameStart = nameStart;
              token.nameEnd = nameEnd;

              const { definitionEnd } = scanToEndOfDefinition(s);
              token.range.end = definitionEnd;
              return token;
            }
          }
        }
        break;
      }
      // Variable, Constant, Class, Enum
      case "v":
      case "c":
      case "e": {
        let tokenType: TokenType;
        if (peekString(s, "var ")) {
          tokenType = TokenType.Variable;
        } else if (peekString(s, "const ")) {
          tokenType = TokenType.Constant;
        } else if (peekString(s, "class ")) {
          tokenType = TokenType.Class;
        } else if (peekString(s, "enum ")) {
          tokenType = TokenType.Enum;
        } else if (peekString(s, "class_name ")) {
          tokenType = TokenType.ClassName;
        } else {
          break;
        }

        advanceToPeek(s);

        const token: Token = {
          tokenType,
          nameStart: 0,
          nameEnd: 0,
          range: {
            start: startPos,
            end: 0,
            definitionStart: startPos,
            definitionEnd: 0,
            bodyStart: 0,
            bodyEnd: 0,
          },
          children: [],
        };

        skipWhitespace(s);

        const { start: nameStart, end: nameEnd } = scanIdentifier(s);
        token.nameStart = nameStart;
        token.nameEnd = nameEnd;

        const { definitionEnd } = scanToEndOfDefinition(s);
        token.range.end = definitionEnd;
        token.range.definitionEnd = definitionEnd;
        return token;
      }
      // Signal
      case "s": {
        if (matchString(s, "signal")) {
          const token: Token = {
            tokenType: TokenType.Signal,
            nameStart: 0,
            nameEnd: 0,
            range: {
              start: startPos,
              end: 0,
              definitionStart: startPos,
              definitionEnd: 0,
              bodyStart: 0,
              bodyEnd: 0,
            },
            children: [],
          };

          skipWhitespace(s);

          const { start: nameStart, end: nameEnd } = scanIdentifier(s);
          token.nameStart = nameStart;
          token.nameEnd = nameEnd;

          // Handle signal arguments if present
          skipWhitespace(s);
          if (getCurrentChar(s) === "(") {
            let bracketCount = 0;
            while (!isAtEnd(s)) {
              const c = getCurrentChar(s);
              if (c === "(") {
                bracketCount++;
                s.current++;
              } else if (c === ")") {
                bracketCount--;
                s.current++;
                if (bracketCount === 0) {
                  break;
                }
              } else {
                s.current++;
              }
            }
          } else {
            scanToStartOfNextLine(s);
          }

          token.range.end = s.current;
          console.debug(`Parsed signal token: ${token}`);
          return token;
        }
        break;
      }
    }

    s.current++;
    console.debug(`Skipping character, current index: ${s.current}`);
  }

  return {
    tokenType: TokenType.Invalid,
    nameStart: 0,
    nameEnd: 0,
    range: {
      start: 0,
      end: 0,
      definitionStart: 0,
      definitionEnd: 0,
      bodyStart: 0,
      bodyEnd: 0,
    },
    children: [],
  };
};

const parseClass = (s: Scanner, classToken: Token): void => {
  // Parses the body of a class, collecting child tokens
  const classIndent = s.indentLevel;
  s.current = classToken.range.bodyStart;

  while (!isAtEnd(s)) {
    console.debug(`Parsing class body. Current index: ${s.current}`);
    // Problem: s is on the first char of the token instead of the beginning of the line
    const currentIndent = countIndentationAndAdvance(s);
    console.debug(`Current indent: ${currentIndent}`);

    if (currentIndent <= classIndent) {
      if (isAtStartOfDefinition(s)) {
        break;
      }
    }

    const childToken = scanNextToken(s);
    if (childToken.tokenType !== TokenType.Invalid) {
      classToken.children.push(childToken);
    }
  }
};

const parseGDScript = (source: string): Token[] => {
  const scanner: Scanner = {
    source: source,
    current: 0,
    indentLevel: 0,
    bracketDepth: 0,
    peekIndex: 0,
  };

  const tokens: Token[] = [];
  while (!isAtEnd(scanner)) {
    const token = scanNextToken(scanner);
    if (token.tokenType === TokenType.Invalid) {
      continue;
    }

    if (token.tokenType === TokenType.Class) {
      token.range.bodyStart = scanner.current;
      parseClass(scanner, token);
      token.range.bodyEnd = scanner.current;
      token.range.end = scanner.current;
    }
    tokens.push(token);
  }
  return tokens;
};

const parseGDScriptFile = async (path: string): Promise<void> => {
  // Parses a GDScript file and caches it in the gdscriptFiles table.
  // The parsing happens in two passes:
  //
  // 1. We preprocess the source code to extract the code between anchor comments and remove these comment lines.
  // 2. We parse the preprocessed source code to tokenize symbols and their content.
  //
  // Preprocessing makes the symbol parsing easier afterwards, although it means we scan the file twice.
  const source = await Deno.readTextFile(path);
  const { anchors, processed: processedSource } = preprocessAnchors(source);
  const tokens = parseGDScript(processedSource);
  const symbols = new Map<string, Token>();

  for (const token of tokens) {
    const name = getName(token, processedSource);
    symbols.set(name, token);
  }

  gdscriptFiles.set(path, {
    filePath: path,
    source: source,
    symbols: symbols,
    anchors: anchors,
    processedSource: processedSource,
  });
};

const parseSymbolQuery = (query: string, filePath: string): SymbolQuery => {
  // Turns a symbol query string like ClassName.body or ClassName.function.definition
  // into a SymbolQuery object for easier processing.
  const parts = query.split(".");

  const result: SymbolQuery = {
    name: parts[0],
    isDefinition: false,
    isBody: false,
    isClass: false,
    childName: "",
  };

  if (parts.length === 2) {
    if (parts[1] === "definition" || parts[1] === "def") {
      result.isDefinition = true;
    } else if (parts[1] === "body") {
      result.isBody = true;
    } else {
      result.childName = parts[1];
      result.isClass = true;
    }
  } else if (parts.length === 3) {
    if (parts[2] === "definition" || parts[2] === "def") {
      result.childName = parts[1];
      result.isClass = true;
      result.isDefinition = true;
    } else if (parts[2] === "body") {
      result.childName = parts[1];
      result.isClass = true;
      result.isBody = true;
    } else {
      addError(`Invalid symbol query: '${query}'`, filePath);
    }
  }

  return result;
};

// TODO: I wrote the functions excluding the end of the range (..<) but I don't
// remember why. It works, but it's an extra implementation detail to keep in
// mind during parsing. Consider changing this to include the end of the range
// (then the index ranges in all procs will need to be adjusted accordingly).
const getCode = (token: Token, preprocessedSource: string): string => {
  // Returns the code of a token given the source code.
  return preprocessedSource.substring(token.range.start, token.range.end);
};

const getName = (token: Token, preprocessedSource: string): string => {
  // Returns the name of a token as a string given the source code.
  return preprocessedSource.substring(token.nameStart, token.nameEnd);
};

const getDefinition = (token: Token, preprocessedSource: string): string => {
  // Returns the definition of a token as a string given the source code.
  return preprocessedSource.substring(
    token.range.definitionStart,
    token.range.definitionEnd,
  );
};

const getBody = (token: Token, preprocessedSource: string): string => {
  // Returns the body of a token as a string given the source code.
  return preprocessedSource.substring(
    token.range.bodyStart,
    token.range.bodyEnd,
  );
};

const getCodeForSymbol = (symbolQuery: string, filePath: string): string => {
  // Gets the code of a symbol given a query and the path to the file
  // The query can be:
  //
  // - A symbol name like a function or class name
  // - The path to a symbol, like ClassName.functionName
  // - The request of a definition, like ClassName.functionName.definition
  // - The request of a body, like ClassName.functionName.body

  const getTokenFromCache = (symbolName: string, filePath: string): Token => {
    // Gets a token from the cache given a symbol name and the path to the
    // GDScript file. Assumes the file is already parsed.
    const file = gdscriptFiles.get(filePath)!;
    if (!file.symbols.has(symbolName)) {
      addError(
        `Symbol not found: '${symbolName}' in file: '${filePath}'. Were you looking to include an anchor instead of a symbol?\nFilling code with empty string.`,
        filePath,
      );
    }

    return file.symbols.get(symbolName)!;
  };

  const query = parseSymbolQuery(symbolQuery, filePath);

  if (!gdscriptFiles.has(filePath)) {
    console.debug(`${filePath} not in cache. Parsing file...`);
    parseGDScriptFile(filePath);
  }

  const file = gdscriptFiles.get(filePath)!;

  // If the query is a class we get the class token and loop through its
  // children, returning as soon as we find the symbol.
  if (query.isClass) {
    const classToken = getTokenFromCache(query.name, filePath);
    if (classToken.tokenType !== TokenType.Class) {
      addError(
        `Symbol '${query.name}' is not a class in file: '${filePath}'`,
        filePath,
      );
      return "";
    }

    for (const child of classToken.children) {
      if (getName(child, file.processedSource) === query.childName) {
        if (query.isDefinition) {
          return getDefinition(child, file.processedSource);
        } else if (query.isBody) {
          return getBody(child, file.processedSource);
        } else {
          return getCode(child, file.processedSource);
        }
      }
    }

    addError(
      `Symbol not found: '${query.childName}' in class '${query.name}'`,
      filePath,
    );
    return "";
  }

  // For other symbols we get the token, ensure that it exists and is valid.
  const token = getTokenFromCache(query.name, filePath);
  if (token.tokenType === TokenType.Invalid) {
    addError(
      `Symbol '${query.name}' not found in file: '${filePath}'`,
      filePath,
    );
    return "";
  }

  if (query.isDefinition) {
    return getDefinition(token, file.processedSource).trimEnd();
  } else if (query.isBody) {
    if (
      token.tokenType !== TokenType.Class &&
      token.tokenType !== TokenType.Function
    ) {
      addError(
        `Symbol '${query.name}' is not a class or function in file: '${filePath}'. Cannot get body: only functions and classes have a body.`,
        filePath,
      );
      return "";
    }
    return getBody(token, file.processedSource);
  } else {
    return getCode(token, file.processedSource);
  }
};

const getCodeForAnchor = (anchorName: string, filePath: string): string => {
  // Gets the code between anchor comments given the anchor name and the path to the file
  if (!gdscriptFiles.has(filePath)) {
    console.debug(`${filePath} not in cache. Parsing file...`);
    parseGDScriptFile(filePath);
  }

  const file = gdscriptFiles.get(filePath)!;
  if (!file.anchors.has(anchorName)) {
    addError(
      `Anchor '${anchorName}' not found in file: '${filePath}'`,
      filePath,
    );
    return "";
  }

  const anchor = file.anchors.get(anchorName)!;
  const code = file.source.substring(anchor.codeStart, anchor.codeEnd);
  return code.split("\n")
    .filter((line) => !line.includes("ANCHOR:") && !line.includes("END:"))
    .join("\n");
};

const getCodeWithoutAnchors = (filePath: string): string => {
  // Gets the preprocessed code of a GDScript file. It's the full script without
  // the anchor tag lines like #ANCHOR:anchor_name or #END:anchor_name
  if (!gdscriptFiles.has(filePath)) {
    console.debug(`${filePath} not in cache. Parsing file...`);
    parseGDScriptFile(filePath);
  }

  const file = gdscriptFiles.get(filePath)!;
  return file.processedSource;
};

// Tests for the GDScript parser
Deno.test("Parse signals", () => {
  const code = `
signal health_depleted
signal health_changed(old_health: int, new_health: int)
		`;
  const tokens = parseGDScript(code);
  assertEquals(tokens.length, 2);
  if (tokens.length === 2) {
    assertEquals(tokens[0].tokenType, TokenType.Signal);
    assertEquals(getName(tokens[0], code), "health_depleted");
    assertEquals(tokens[1].tokenType, TokenType.Signal);
    assertEquals(getName(tokens[1], code), "health_changed");
  }
});

Deno.test("Parse enums", () => {
  const code = `
		enum Direction {UP, DOWN, LEFT, RIGHT}
		enum Events {
				NONE,
				FINISHED,
		}
		`;
  const tokens = parseGDScript(code);
  assertEquals(tokens.length, 2);
  if (tokens.length === 2) {
    assertEquals(tokens[0].tokenType, TokenType.Enum);
    assertEquals(getName(tokens[0], code), "Direction");
    assertEquals(tokens[1].tokenType, TokenType.Enum);
    assertEquals(getName(tokens[1], code), "Events");
  }
});

Deno.test("Parse variables", () => {
  const code = `
@export var skin: MobSkin3D = null
@export_range(0.0, 10.0) var power := 0.1
var dynamic_uninitialized
var health := max_health
`;
  const tokens = parseGDScript(code);
  assertEquals(tokens.length, 4);
  if (tokens.length === 4) {
    assertEquals(tokens[0].tokenType, TokenType.Variable);
    assertEquals(getName(tokens[0], code), "skin");
    assertEquals(tokens[1].tokenType, TokenType.Variable);
    assertEquals(getName(tokens[1], code), "power");
    assertEquals(tokens[2].tokenType, TokenType.Variable);
    assertEquals(getName(tokens[2], code), "dynamic_uninitialized");
    assertEquals(tokens[3].tokenType, TokenType.Variable);
    assertEquals(getName(tokens[3], code), "health");
  }
});

Deno.test("Parse constants", () => {
  const code = "const MAX_HEALTH = 100";
  const tokens = parseGDScript(code);
  assertEquals(tokens.length, 1);
  if (tokens.length === 1) {
    assertEquals(tokens[0].tokenType, TokenType.Constant);
    assertEquals(getName(tokens[0], code), "MAX_HEALTH");
  }
});

Deno.test("Parse functions", () => {
  const code = `
func _ready():
	add_child(skin)

func deactivate() -> void:
	if hurt_box != null:
		(func deactivate_hurtbox():
			hurt_box.monitoring = false
			hurt_box.monitorable = false).call_deferred()
`;
  const tokens = parseGDScript(code);
  assertEquals(tokens.length, 2);
  if (tokens.length === 2) {
    assertEquals(tokens[0].tokenType, TokenType.Function);
    assertEquals(getName(tokens[0], code), "_ready");
    assertEquals(tokens[1].tokenType, TokenType.Function);
    assertEquals(getName(tokens[1], code), "deactivate");
  }
});

Deno.test("Parse inner class", () => {
  const code = `
class StateMachine extends Node:
	var transitions := {}: set = set_transitions
	var current_state: State
	var is_debugging := false: set = set_is_debugging

	func _init() -> void:
		set_physics_process(false)
		var blackboard := Blackboard.new()
		Blackboard.player_died.connect(trigger_event.bind(Events.PLAYER_DIED))
`;
  const tokens = parseGDScript(code);
  assertEquals(tokens.length, 1);
  if (tokens.length === 1) {
    const classToken = tokens[0];
    assertEquals(classToken.tokenType, TokenType.Class);
    assertEquals(getName(classToken, code), "StateMachine");
    assertEquals(classToken.children.length, 4);
    assertEquals(classToken.children[0].tokenType, TokenType.Variable);
    assertEquals(classToken.children[1].tokenType, TokenType.Variable);
    assertEquals(classToken.children[2].tokenType, TokenType.Variable);
    assertEquals(classToken.children[3].tokenType, TokenType.Function);
  }
});

Deno.test("Parse larger inner class with anchors", () => {
  const code = `
#ANCHOR:class_StateDie
class StateDie extends State:

	const SmokeExplosionScene = preload("res://assets/vfx/smoke_vfx/smoke_explosion.tscn")

	#ANCHOR:test
	func _init(init_mob: Mob3D) -> void:
		super("Die", init_mob)

	func enter() -> void:
		mob.skin.play("die")
		#END:test

		var smoke_explosion := SmokeExplosionScene.instantiate()
		mob.add_sibling(smoke_explosion)
		smoke_explosion.global_position = mob.global_position

		mob.skin.animation_finished.connect(func (_animation_name: String) -> void:
			mob.queue_free()
		)
#END:class_StateDie
`;
  const { processed: processedSource } = preprocessAnchors(code);
  const tokens = parseGDScript(processedSource);
  assertEquals(tokens.length, 1);
  if (tokens.length === 1) {
    const classToken = tokens[0];
    assertEquals(classToken.tokenType, TokenType.Class);
    assertEquals(getName(classToken, processedSource), "StateDie");
    assertEquals(classToken.children.length, 3);
    // Trailing anchor comments should not be included in the token
    assert(!getBody(classToken, processedSource).includes("#END"));
  } else {
    console.log("Found tokens: ", tokens.length);
    printTokens(tokens, processedSource);
  }
});

Deno.test("Anchor after docstring", () => {
  const code = `
## The words that appear on screen at each step.
#ANCHOR:counting_steps
@export var counting_steps: Array[String]= ["3", "2", "1", "GO!"]
#END:counting_steps
`;
  const { processed: processedSource } = preprocessAnchors(code);
  const tokens = parseGDScript(processedSource);
  assertEquals(tokens.length, 1);
  if (tokens.length === 1) {
    const token = tokens[0];
    assertEquals(token.tokenType, TokenType.Variable);
    assertEquals(getName(token, processedSource), "counting_steps");
  }
});

Deno.test("Another anchor", () => {
  const code = `
## The container for buttons
#ANCHOR:010_the_container_box
@onready var action_buttons_v_box_container: VBoxContainer = %ActionButtonsVBoxContainer
#END:010_the_container_box
`;
  const { processed: processedSource } = preprocessAnchors(code);
  const tokens = parseGDScript(processedSource);
  assertEquals(tokens.length, 1);
  if (tokens.length === 1) {
    const token = tokens[0];
    assertEquals(token.tokenType, TokenType.Variable);
    assertEquals(
      getName(token, processedSource),
      "action_buttons_v_box_container",
    );
  }
});

Deno.test("Parse anchor code", async () => {
  const code = `
#ANCHOR:row_node_references
@onready var row_bodies: HBoxContainer = %RowBodies
@onready var row_expressions: HBoxContainer = %RowExpressions
#END:row_node_references
`;
  const tempFile = await Deno.makeTempFile({ suffix: ".gd" });
  await Deno.writeTextFile(tempFile, code);
  const rowNodeReferences = getCodeForAnchor("row_node_references", tempFile);
  await Deno.remove(tempFile);

  assert(
    rowNodeReferences.includes("var row_bodies: HBoxContainer = %RowBodies"),
  );
  assert(
    rowNodeReferences.includes(
      "var row_expressions: HBoxContainer = %RowExpressions",
    ),
  );
});

Deno.test("Parse func followed by var with docstring", () => {
  const code = `
func _ready() -> void:
	test()

## The player's health.
var health := 100
`;
  const tokens = parseGDScript(code);
  assertEquals(tokens.length, 2);
  assertEquals(tokens[0].tokenType, TokenType.Function);
  assertEquals(getName(tokens[0], code), "_ready");
  assert(!getBody(tokens[0], code).includes("## The player's health."));
  assertEquals(tokens[1].tokenType, TokenType.Variable);
  assertEquals(getName(tokens[1], code), "health");
});

Deno.test("Parse and output variable by symbol name", () => {
  const code = `
const PHYSICS_LAYER_MOBS = 2

@export var mob_detection_range := 400.0
@export var attack_rate := 1.0
@export var max_rotation_speed := 2.0 * PI
`;
  const { processed: processedSource } = preprocessAnchors(code);
  const tokens = parseGDScript(processedSource);
  let mobDetectionRangeToken: Token | undefined;
  for (const token of tokens) {
    if (getName(token, processedSource) === "mob_detection_range") {
      mobDetectionRangeToken = token;
      break;
    }
  }
  const mobDetectionRange = getCode(mobDetectionRangeToken!, processedSource);
  assertEquals(mobDetectionRange, "@export var mob_detection_range := 400.0");
});

Deno.test("Parse multiple annotated variables by symbol name", () => {
  const code = `
@export var speed := 350.0

var _traveled_distance := 0.0

func test():
	pass
`;
  const { processed: processedSource } = preprocessAnchors(code);
  const tokens = parseGDScript(processedSource);

  let speedToken: Token | undefined;
  let traveledDistanceToken: Token | undefined;

  for (const token of tokens) {
    if (getName(token, processedSource) === "speed") {
      speedToken = token;
    } else if (getName(token, processedSource) === "_traveled_distance") {
      traveledDistanceToken = token;
    }
  }

  const speedCode = getCode(speedToken!, processedSource);
  const traveledDistanceCode = getCode(traveledDistanceToken!, processedSource);

  assertEquals(speedCode, "@export var speed := 350.0");
  assertEquals(traveledDistanceCode, "var _traveled_distance := 0.0");
});

Deno.test("Parse class_name", () => {
  const code = `
class_name Mob3D extends Node3D

	var test = 5
`;
  const tokens = parseGDScript(code);
  assertEquals(tokens.length, 2);
  if (tokens.length === 2) {
    assertEquals(tokens[0].tokenType, TokenType.ClassName);
    assertEquals(getName(tokens[0], code), "Mob3D");
    assertEquals(getCode(tokens[0], code), "class_name Mob3D extends Node3D");
    assertEquals(tokens[1].tokenType, TokenType.Variable);
    assertEquals(getName(tokens[1], code), "test");
  }
});

Deno.test("Extract property with annotation on previous line", () => {
  const code = `
@export_category("Ground movement")
@export_range(1.0, 10.0, 0.1) var max_speed_jog := 4.0
`;

  const { processed: processedSource } = preprocessAnchors(code);
  const tokens = parseGDScript(processedSource);

  let maxSpeedJogToken: Token | undefined;
  for (const token of tokens) {
    if (getName(token, processedSource) === "max_speed_jog") {
      maxSpeedJogToken = token;
      break;
    }
  }

  const maxSpeedJogCode = getCode(maxSpeedJogToken!, processedSource);
  assertEquals(
    maxSpeedJogCode,
    "@export_range(1.0, 10.0, 0.1) var max_speed_jog := 4.0",
  );
  assert(!maxSpeedJogCode.includes("@export_category"));
});

Deno.test("Parse multiple anchors", () => {
  const code = `
func set_is_active(value: bool) -> void:
	#ANCHOR: is_active_toggle_active
	is_active = value
	_static_body_collision_shape.disabled = is_active
	#END: is_active_toggle_active

	#ANCHOR: is_active_animation
	var top_value := 1.0 if is_active else 0.0
	#END: is_active_animation`;
  const { anchors } = preprocessAnchors(code);
  assertEquals(anchors.size, 2);
  assert(anchors.has("is_active_toggle_active"));
  assert(anchors.has("is_active_animation"));
});

// Deno.test("Performance test", () => {
//   const codeTest = `
// class StateMachine extends Node:
// 	var transitions := {}: set = set_transitions
// 	var current_state: State
// 	var is_debugging := false: set = set_is_debugging

// 	func _init() -> void:
// 		set_physics_process(false)
// 		var blackboard := Blackboard.new()
// 		Blackboard.player_died.connect(trigger_event.bind(Events.PLAYER_DIED))
//   `;

//   console.log("Running performance test...");
//   let totalDuration = 0;

//   for (let i = 0; i < 10; i++) {
//     const start = performance.now();
//     for (let j = 0; j < 10_000; j++) {
//       parseGDScript(codeTest);
//     }
//     const duration = performance.now() - start;
//     totalDuration += duration;
//   }

//   const averageDuration = totalDuration / 10;
//   console.log(`Average parse duration for 10 000 calls: ${averageDuration.toFixed(3)}ms`);
//   console.log(
//     `For ${10_000 * codeTest.length} characters and ${
//       codeTest.split('\n').length * 10_000
//     } lines of code`
//   );
// });
