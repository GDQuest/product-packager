#!/usr/bin/env deno --allow-run --allow-read --allow-write

/**
 * A range of character indices in a source string or in a sequence of nodes.
 */
interface Range {
  start: number;
  end: number;
}

/**
 * Error thrown during parsing of MDX content
 */
class ParseError extends Error {
  range: Range;

  constructor(range: Range, message: string) {
    super(message);
    this.range = range;
    this.name = "ParseError";
  }
}

/**
 * Possible types of MDX component attributes
 */
enum AttributeKind {
  Boolean,
  Number,
  String,
  JsxExpression,
}

/**
 * Represents an attribute in an MDX component
 */
type Attribute = {
  range: Range;
  name: Range;
  kind: AttributeKind;
} & (
    | { kind: AttributeKind.Boolean; boolValue: boolean }
    | { kind: AttributeKind.JsxExpression; jsxValue: unknown }
    | { kind: AttributeKind.Number | AttributeKind.String; value: Range }
  );

/**
 * Possible types of MDX nodes
 */
enum NodeKind {
  MdxComponent,
  MarkdownContent,
}

/**
 * Base interface for MDX nodes
 */
interface BaseNode {
  range: Range;
  children: Node[];
  kind: NodeKind;
}

/**
 * Represents an MDX component node
 */
interface MdxComponentNode extends BaseNode {
  kind: NodeKind.MdxComponent;
  name: Range;
  attributes: Attribute[];
  isSelfClosing: boolean;
}

/**
 * Represents a markdown content node
 */
interface MarkdownContentNode extends BaseNode {
  kind: NodeKind.MarkdownContent;
}

/**
 * Union type for all node kinds
 */
type Node = MdxComponentNode | MarkdownContentNode;

/**
 * Position in a source document for error reporting
 */
interface Position {
  line: number;
  column: number;
}

// Precompiled regex patterns for better performance
const WHITESPACE_REGEX = /^[ \t\n\r]+/;
const IDENTIFIER_REGEX = /^[a-zA-Z0-9_]+/;
const UPPERCASE_REGEX = /^[A-Z]/;
const MDX_TAG_START_REGEX = /^<[A-Z]/;
const MDX_CLOSING_TAG_START_REGEX = /^<\//;
const STRING_CONTENT_REGEX = (quote: string) => new RegExp(`^[^${quote}]*`);
const JSX_EXPRESSION_REGEX = /^[^{}]*(?:{[^{}]*}[^{}]*)*/;

// Character test functions for single characters
const isWhitespace = (c: string): boolean => /[ \t\n\r]/.test(c);
const isUppercaseAscii = (c: string): boolean => /[A-Z]/.test(c);
const isAlphanumericOrUnderscore = (c: string): boolean => /[a-zA-Z0-9_]/.test(c);

/**
 * Scanner class for parsing MDX content
 */
class Scanner {
  readonly source: string;
  index: number;
  peekIndex: number;
  nodes: Node[];

  // Cache for line start indices
  private _lineStartIndices: number[] | null = null;

  constructor(source: string) {
    this.source = source;
    this.index = 0;
    this.peekIndex = 0;
    this.nodes = [];
  }

  /**
   * Returns the current character at the scanner position
   */
  currentChar(): string {
    return this.source[this.index] || "\0";
  }

  /**
   * Returns the character at the specified position
   */
  getChar(at: number): string {
    return this.source[at] || "\0";
  }

  /**
   * Returns the substring defined by the range
   */
  getString(range: Range): string {
    return this.source.substring(range.start, range.end);
  }

  /**
   * Returns true if the scanner has reached the end of the source string
   */
  isAtEnd(): boolean {
    return this.index >= this.source.length;
  }

  /**
   * Advances the scanner index by the given offset
   */
  advance(offset = 1): number {
    this.index += offset;
    return this.index;
  }

  /**
   * Returns the character at the current position plus offset without advancing the scanner
   */
  peek(offset = 1): string {
    this.peekIndex = this.index + offset;
    return this.peekIndex >= this.source.length
      ? "\0"
      : this.source[this.peekIndex];
  }

  /**
   * Advances the scanner to the peek index
   */
  advanceToPeek(): number {
    this.index = this.peekIndex;
    return this.index;
  }

  /**
   * Advances the scanner until it finds a non-whitespace character
   * Uses regex to skip multiple whitespace characters at once
   */
  skipWhitespace(): void {
    const match = WHITESPACE_REGEX.exec(this.source.slice(this.index));
    if (match) {
      this.index += match[0].length;
    }
  }

  /**
   * Returns true if the next chars in the scanner match the expected string
   */
  matchString(expected: string): boolean {
    if (this.source.startsWith(expected, this.index)) {
      this.index += expected.length;
      return true;
    }
    return false;
  }

  /**
   * Advances the scanner and returns true if the current character matches the expected char
   */
  matchChar(expected: string): boolean {
    if (this.index < this.source.length && this.source[this.index] === expected) {
      this.advance();
      return true;
    }
    return false;
  }

  /**
   * Scans and returns the range of an identifier in the source string
   * Uses regex to match the entire identifier at once
   */
  scanIdentifier(): Range {
    const start = this.index;
    const match = IDENTIFIER_REGEX.exec(this.source.slice(this.index));

    if (match) {
      this.index += match[0].length;
    }

    return { start, end: this.index };
  }

  /**
   * Returns true if the scanner is at the start of an MDX component
   * Uses regex to check for "<" followed by uppercase letter
   */
  isMdxComponentStart(): boolean {
    return MDX_TAG_START_REGEX.test(this.source.slice(this.index));
  }

  /**
   * Returns true if the scanner is at the start of an MDX component closing tag
   * Uses regex to check for "</"
   */
  isMdxClosingTagStart(): boolean {
    return MDX_CLOSING_TAG_START_REGEX.test(this.source.slice(this.index));
  }

  /**
   * Returns true if the scanner is at the start of any MDX tag
   */
  isMdxTagStart(): boolean {
    const char = this.currentChar();
    if (char !== '<') return false;

    const nextChar = this.peek();
    return isUppercaseAscii(nextChar) || nextChar === '/';
  }

  /**
   * Finds the start indices of each line in the source string
   */
  getLineStartIndices(): number[] {
    // Cache the result for better performance
    if (this._lineStartIndices !== null) {
      return this._lineStartIndices;
    }

    const result = [0];
    const { source } = this;

    for (let i = 0; i < source.length; i++) {
      if (source[i] === "\n") {
        result.push(i + 1);
      }
    }

    this._lineStartIndices = result;
    return result;
  }

  /**
   * Returns the position (line and column) for the current index
   */
  position(): Position {
    const lineStartIndices = this.getLineStartIndices();

    // Use binary search for faster line lookup
    let low = 0;
    let high = lineStartIndices.length - 1;

    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      const midValue = lineStartIndices[mid];

      if (this.index < midValue) {
        high = mid - 1;
      } else if (mid < lineStartIndices.length - 1 && this.index >= lineStartIndices[mid + 1]) {
        low = mid + 1;
      } else {
        return {
          line: mid + 1,
          column: this.index - midValue + 1
        };
      }
    }

    // Fallback
    return { line: 1, column: 1 };
  }

  /**
   * Returns the current line of text at the scanner position
   */
  currentLine(): string {
    const lineStartIndices = this.getLineStartIndices();
    let lineStart = 0;

    // Find the start of the current line
    for (const start of lineStartIndices) {
      if (start <= this.index) {
        lineStart = start;
      } else {
        break;
      }
    }

    // Find the end of the line
    let lineEnd = lineStart;
    while (lineEnd < this.source.length && this.source[lineEnd] !== "\n") {
      lineEnd++;
    }

    return this.source.substring(lineStart, lineEnd);
  }

  /**
   * Scans to the end of a string literal
   * @param quoteChar The quote character that started the string
   * @returns The position after the closing quote
   */
  scanStringLiteral(quoteChar: string): number {
    const start = this.index;
    // Move past the opening quote
    this.advance();

    // Use regex to scan up to the closing quote
    const match = STRING_CONTENT_REGEX(quoteChar).exec(this.source.slice(this.index));
    if (match) {
      this.index += match[0].length;
    }

    // Check for closing quote
    if (this.currentChar() === quoteChar) {
      this.advance(); // Move past the closing quote
    }

    return this.index;
  }

  /**
   * Scans to the end of a JSX expression, handling nested braces
   * @returns The position after the closing brace
   */
  scanJsxExpression(): number {
    const start = this.index;
    let depth = 1; // We start after the opening brace
    this.advance(); // Move past the opening brace

    while (!this.isAtEnd() && depth > 0) {
      if (this.currentChar() === '{') {
        depth++;
      } else if (this.currentChar() === '}') {
        depth--;
      }
      this.advance();
    }

    return this.index;
  }
}

/**
 * MDX Component token kinds
 */
enum TokenMdxComponentKind {
  OpeningTagOpen,         // <
  OpeningTagClose,        // >
  OpeningTagSelfClosing,  // />
  ClosingTagOpen,         // </
  Identifier,             // Alphanumeric or underscore
  EqualSign,              // =
  String,                 // "..." or '...'
  Number,                 // 123 or 123.45
  Colon,                  // :
  Comma,                  // ,
  JsxExpression,          // {...}
}

/**
 * Represents a token in an MDX component
 */
interface TokenMdxComponent {
  range: Range;
  kind: TokenMdxComponentKind;
}

/**
 * Parses markdown content until a condition is met
 * Uses regex to quickly find the next MDX tag start
 */
const parseMarkdownContent = (s: Scanner): Node => {
  const start = s.index;

  // Keep track of current position in source
  const source = s.source.slice(s.index);

  // Look for the next MDX tag start
  const nextTagMatch = /<[A-Z\/]/.exec(source);
  if (nextTagMatch) {
    s.index += nextTagMatch.index;
  } else {
    s.index = s.source.length; // No more tags, advance to end
  }

  // Trim whitespace
  let startIndex = start;
  let endIndex = s.index;
  const sourceStr = s.source;

  // Trim leading whitespace
  while (startIndex < endIndex && isWhitespace(sourceStr[startIndex])) {
    startIndex++;
  }

  // Trim trailing whitespace
  while (endIndex > startIndex && isWhitespace(sourceStr[endIndex - 1])) {
    endIndex--;
  }

  return {
    kind: NodeKind.MarkdownContent,
    range: { start: startIndex, end: endIndex },
    children: []
  };
};

/**
 * Scans and tokenizes the contents of a single MDX tag
 */
const tokenizeMdxComponent = (s: Scanner): { range: Range; tokens: TokenMdxComponent[] } => {
  // Assert we're at the start of a tag
  if (s.currentChar() !== "<") {
    throw new Error(`The scanner should be at the start of an MDX tag for this procedure to work. Found \`${s.currentChar()}\` instead.`);
  }

  const result: { range: Range; tokens: TokenMdxComponent[] } = {
    range: { start: s.index, end: 0 },
    tokens: []
  };

  while (!s.isAtEnd()) {
    s.skipWhitespace();
    const currentChar = s.currentChar();

    switch (currentChar) {
      case "<":
        if (s.peek() === "/") {
          result.tokens.push({
            kind: TokenMdxComponentKind.ClosingTagOpen,
            range: { start: s.index, end: s.advance(2) }
          });
        } else {
          result.tokens.push({
            kind: TokenMdxComponentKind.OpeningTagOpen,
            range: { start: s.index, end: s.advance() }
          });
        }
        break;

      case ">":
        if (s.index > 0 && s.getChar(s.index - 1) === "/") {
          const token: TokenMdxComponent = {
            kind: TokenMdxComponentKind.OpeningTagSelfClosing,
            range: { start: s.index - 1, end: s.advance() }
          };
          result.tokens.push(token);
          result.range.end = token.range.end;
        } else {
          result.tokens.push({
            kind: TokenMdxComponentKind.OpeningTagClose,
            range: { start: s.index, end: s.advance() }
          });
        }
        result.range.end = s.index;
        return result;

      case "=":
        result.tokens.push({
          kind: TokenMdxComponentKind.EqualSign,
          range: { start: s.index, end: s.advance() }
        });
        break;

      case '"':
      case "'":
        const quoteChar = currentChar;
        const start = s.index;
        const end = s.scanStringLiteral(quoteChar);

        if (s.isAtEnd() && s.getChar(end - 1) !== quoteChar) {
          throw new ParseError(
            { start, end: s.index },
            `Found string literal opening character in an MDX tag but no closing character. Expected \`${quoteChar}\` character to close the string literal.`
          );
        }

        result.tokens.push({
          kind: TokenMdxComponentKind.String,
          range: { start, end }
        });
        break;

      case "{":
        const bracketStart = s.index;
        s.advance(); // Move past the opening brace

        // Count braces to handle nested expressions
        let depth = 1;
        while (!s.isAtEnd() && depth > 0) {
          if (s.currentChar() === '{') {
            depth++;
          } else if (s.currentChar() === '}') {
            depth--;
          }
          s.advance();
        }

        if (depth !== 0) {
          throw new ParseError(
            { start: bracketStart, end: s.index },
            "Found opening `{` character in an MDX tag but no matching closing character. Expected a `}` character to close the JSX expression."
          );
        }

        result.tokens.push({
          kind: TokenMdxComponentKind.JsxExpression,
          range: { start: bracketStart, end: s.index }
        });
        break;

      default:
        if (isAlphanumericOrUnderscore(currentChar)) {
          result.tokens.push({
            kind: TokenMdxComponentKind.Identifier,
            range: s.scanIdentifier()
          });
        } else {
          s.advance();
        }
    }
  }

  return result;
};

// Forward declarations to handle cyclical calls
const parseNodes = (s: Scanner): Node[] => {
  const result: Node[] = [];

  while (!s.isAtEnd()) {
    if (s.isMdxComponentStart()) {
      result.push(parseMdxComponent(s));
    } else if (s.isMdxClosingTagStart()) {
      break;
    } else {
      result.push(parseMarkdownContent(s));
    }
  }

  return result;
};

/**
 * Parses an MDX component from the scanner's current position
 */
const parseMdxComponent = (s: Scanner): Node => {
  const start = s.index;
  const { range, tokens } = tokenizeMdxComponent(s);

  if (tokens.length < 3) {
    throw new ParseError(
      range,
      "Found a `<` character in the source document but no valid MDX component tag. " +
      "In MDX, `<` marks the start of a component tag, which must contain an identifier and " +
      "be closed with a `>` character or `/>`.\nTo write a literal `<` character in the " +
      "document, escape it as `\\<` or `&lt;`."
    );
  }

  // First token must be opening < and second must be an identifier
  if (tokens[0].kind !== TokenMdxComponentKind.OpeningTagOpen ||
    tokens[1].kind !== TokenMdxComponentKind.Identifier) {
    throw new ParseError(
      range,
      "Expected an opening `<` character followed by an identifier, but found " +
      `\`${s.getString(tokens[0].range)}\` and \`${s.getString(tokens[1].range)}\` instead.`
    );
  }

  // Component name must start with uppercase letter
  const nameToken = tokens[1];
  const firstChar = s.source[nameToken.range.start];
  if (!isUppercaseAscii(firstChar)) {
    throw new ParseError(
      nameToken.range,
      "Expected component name to start with an uppercase letter but found " +
      `${s.getString(nameToken.range)} instead. A valid component name must start with ` +
      "an uppercase letter."
    );
  }

  const result: MdxComponentNode = {
    kind: NodeKind.MdxComponent,
    range: { start, end: 0 },
    name: nameToken.range,
    attributes: [],
    children: [],
    isSelfClosing: false
  };

  // Collect attributes
  let i = 2;
  while (i < tokens.length) {
    const token = tokens[i];

    if (token.kind === TokenMdxComponentKind.OpeningTagClose ||
      token.kind === TokenMdxComponentKind.OpeningTagSelfClosing) {
      break;
    }

    if (token.kind === TokenMdxComponentKind.Identifier) {
      // Boolean attribute (standalone identifier)
      if (i + 1 >= tokens.length ||
        tokens[i + 1].kind === TokenMdxComponentKind.Identifier ||
        tokens[i + 1].kind === TokenMdxComponentKind.OpeningTagClose ||
        tokens[i + 1].kind === TokenMdxComponentKind.OpeningTagSelfClosing) {
        result.attributes.push({
          kind: AttributeKind.Boolean,
          range: token.range,
          name: token.range,
          boolValue: true
        });
      }
      // 'identifier = value' form
      else if (i + 2 < tokens.length && tokens[i + 1].kind === TokenMdxComponentKind.EqualSign) {
        const valueToken = tokens[i + 2];

        if (valueToken.kind === TokenMdxComponentKind.String) {
          result.attributes.push({
            kind: AttributeKind.String,
            range: { start: token.range.start, end: valueToken.range.end },
            name: token.range,
            value: valueToken.range
          });
        } else if (valueToken.kind === TokenMdxComponentKind.JsxExpression) {
          const attrRange = { start: token.range.start, end: valueToken.range.end };
          const jsxRange = { start: valueToken.range.start + 1, end: valueToken.range.end - 1 };

          // Parse JSX expression
          try {
            const jsxValue = JSON.parse(s.getString(jsxRange));
            result.attributes.push({
              kind: AttributeKind.JsxExpression,
              range: attrRange,
              name: token.range,
              jsxValue
            });
          } catch (e) {
            throw new ParseError(
              jsxRange,
              `Failed to parse JSX expression: ${e.message}`
            );
          }
        } else {
          throw new ParseError(
            valueToken.range,
            "Expected `string` or JSX expression as `attribute value`"
          );
        }
        i += 2; // Skip over the = and value tokens
      } else {
        throw new ParseError(
          token.range,
          "Expected `attribute name` to be followed by `=` and a `value`"
        );
      }
    }
    i++;
  }

  // Check if tag is self-closing
  const lastToken = tokens[tokens.length - 1];
  result.isSelfClosing = lastToken.kind === TokenMdxComponentKind.OpeningTagSelfClosing;

  if (!result.isSelfClosing) {
    result.children = parseNodes(s);
    const componentName = s.getString(result.name);

    // Look for closing tag
    const closingTag = "</" + componentName + ">";
    if (!s.matchString(closingTag)) {
      // Try to find it by scanning forward
      while (!s.isAtEnd()) {
        if (s.matchString(closingTag)) {
          break;
        }
        s.advance();
      }
    }
  }

  result.range = { start, end: s.index };
  return result;
};

// Main export functions
export {
  parseNodes,
  ParseError,
  NodeKind,
  AttributeKind
};

// For testing
if (import.meta.main) {
  const runTests = () => {
    console.log("Running tests...");

    const echoTokens = (s: Scanner, tokens: TokenMdxComponent[], indent = 0) => {
      for (const token of tokens) {
        console.log(" ".repeat(indent) + `${TokenMdxComponentKind[token.kind]} | \`${s.getString(token.range)}\``);
      }
    };

    const echoNodes = (s: Scanner, nodes: Node[], indent = 0) => {
      for (const node of nodes) {
        console.log(" ".repeat(indent) + `${NodeKind[node.kind]} | \`${s.getString(node.range)}\``);
        if (node.kind === NodeKind.MdxComponent) {
          echoNodes(s, node.children, indent + 2);
        }
      }
    };

    // Test: tokenize MDX component with string and JSX expression attributes
    {
      console.log("\nTest: tokenize MDX component with string and JSX expression attributes");

      const source = `<SomeComponent prop1="value1" prop2={"value2"}>
    Some text
</SomeComponent>`;

      const scanner = new Scanner(source);
      const { range, tokens } = tokenizeMdxComponent(scanner);

      console.assert(tokens.length === 9, "Expected 9 tokens");
      console.assert(tokens[0].kind === TokenMdxComponentKind.OpeningTagOpen, "First token should be opening tag");
      console.assert(tokens[1].kind === TokenMdxComponentKind.Identifier, "Second token should be identifier");
      console.assert(tokens[2].kind === TokenMdxComponentKind.Identifier, "Third token should be identifier (prop1)");
      console.assert(tokens[3].kind === TokenMdxComponentKind.EqualSign, "Fourth token should be equal sign");
      console.assert(tokens[4].kind === TokenMdxComponentKind.String, "Fifth token should be string");
      console.assert(tokens[5].kind === TokenMdxComponentKind.Identifier, "Sixth token should be identifier (prop2)");
      console.assert(tokens[6].kind === TokenMdxComponentKind.EqualSign, "Seventh token should be equal sign");
      console.assert(tokens[7].kind === TokenMdxComponentKind.JsxExpression, "Eighth token should be JSX expression");
      console.assert(tokens[8].kind === TokenMdxComponentKind.OpeningTagClose, "Ninth token should be closing tag");

      console.log("Test passed!");
    }

    // Test: parse self-closing mdx node
    {
      console.log("\nTest: parse self-closing mdx node");

      const source = `<SomeComponent prop1="value1" prop2={"value2"}   />`;
      const scanner = new Scanner(source);
      const node = parseMdxComponent(scanner);

      echoNodes(scanner, [node]);

      console.assert(node.kind === NodeKind.MdxComponent, "Node should be MDX component");
      console.assert(scanner.getString(node.name) === "SomeComponent", "Component name should be 'SomeComponent'");
      console.assert(node.isSelfClosing, "Component should be self-closing");
      console.assert(node.attributes.length === 2, "Component should have 2 attributes");
      console.assert(scanner.getString(node.attributes[0].name) === "prop1", "First attribute name should be 'prop1'");
      console.assert(scanner.getString(node.attributes[0].value) === "\"value1\"", "First attribute value should be '\"value1\"'");
      console.assert(scanner.getString(node.attributes[1].name) === "prop2", "Second attribute name should be 'prop2'");
      console.assert(node.attributes[1].kind === AttributeKind.JsxExpression, "Second attribute should be JSX expression");
      console.assert(node.attributes[1].jsxValue === "value2", "Second attribute value should be 'value2'");

      console.log("Test passed!");
    }

    // Test: parse nested components and markdown
    {
      console.log("\nTest: parse nested components and markdown");

      const source = `
<OuterComponent>
  Some text with *markdown* formatting and an ![inline image](images/image.png).
  <InnerComponent prop="value">
    Nested **markdown** content.
  </InnerComponent>
  More text after the inner component.
</OuterComponent>`;

      const scanner = new Scanner(source);
      const nodes = parseNodes(scanner);

      echoNodes(scanner, nodes);

      console.assert(nodes.length === 1, "There should be 1 root node");
      console.assert(nodes[0].kind === NodeKind.MdxComponent, "Root node should be MDX component");
      console.assert(scanner.getString(nodes[0].name) === "OuterComponent", "Root component name should be 'OuterComponent'");
      console.assert(nodes[0].attributes.length === 0, "Root component should have no attributes");
      console.assert(nodes[0].children.length > 0, "Root component should have children");
      console.assert(nodes[0].children[0].kind === NodeKind.MarkdownContent, "First child should be markdown content");
      console.assert(nodes[0].children[1].kind === NodeKind.MdxComponent, "Second child should be MDX component");
      console.assert(scanner.getString(nodes[0].children[1].name) === "InnerComponent", "Inner component name should be 'InnerComponent'");
      console.assert(nodes[0].children[1].attributes.length === 1, "Inner component should have 1 attribute");
      console.assert(scanner.getString(nodes[0].children[1].attributes[0].name) === "prop", "Inner component attribute name should be 'prop'");
      console.assert(nodes[0].children[1].attributes[0].kind === AttributeKind.String, "Inner component attribute should be string");
      console.assert(scanner.getString(nodes[0].children[1].attributes[0].value) === "\"value\"", "Inner component attribute value should be '\"value\"'");
      console.assert(nodes[0].children[1].children.length > 0, "Inner component should have children");
      console.assert(nodes[0].children[1].children[0].kind === NodeKind.MarkdownContent, "Inner component's child should be markdown content");
      console.assert(nodes[0].children[2].kind === NodeKind.MarkdownContent, "Third child of root should be markdown content");
      console.assert(scanner.getString(nodes[0].children[2].range).trim() === "More text after the inner component.", "Third child content should match");

      console.log("Test passed!");
    }

    console.log("\nAll tests completed!");
  };

  runTests();
}
