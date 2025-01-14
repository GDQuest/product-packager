# GDQuest's MDX parser

Minimal MDX parser for the needs of the GDQuest atform.

This parser is a work in progress.

It is not meant to become a full mmonmark-compliant parser: many markdown
features are replaced well with react or web mponents.
Instead, this parser aims to run fast and be easy  maintain.

Algorithm:
1. Tokenize into smaller tokens
2. Find block-level tokens (e.g. code blocks, mdx mponents) from the tokens
3. parse the block tokens in greater detail and find their significant elements
