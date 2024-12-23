import std/[strformat]

type Report* = object
    built*: int
    errors*: int
    skipped*: int

proc `$`*(r: Report): string =
  fmt"Summary: {r.built} built, {r.errors} errors, {r.skipped} skipped."
