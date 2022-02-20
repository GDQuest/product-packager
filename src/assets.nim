import std/strformat


const
  CACHE_COURSE_CSS_NAME* = "course.css"
  CACHE_COURSE_CSS* = staticRead(fmt"../assets/{CACHE_COURSE_CSS_NAME}")

  CACHE_GDSCRIPT_DEF_NAME* = "gdscript.xml"
  CACHE_GDSCRIPT_DEF* = staticRead(fmt"../assets/{CACHE_GDSCRIPT_DEF_NAME}")

  CACHE_GDSCRIPT_THEME_NAME* = "gdscript.theme"
  CACHE_GDSCRIPT_THEME* = staticRead(fmt"../assets/{CACHE_GDSCRIPT_THEME_NAME}")
