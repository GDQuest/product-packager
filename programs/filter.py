"""
Pandoc filter to convert all level 2+ headers to paragraphs with
emphasized text.
"""

from pandocfilters import toJSONFilter, Emph, Para, Header


def behead(key, value, format, meta):
    if key == 'Header':
        value[0] += 1
        return Header(value[0], value[1], value[2])


if __name__ == "__main__":
  toJSONFilter(behead)