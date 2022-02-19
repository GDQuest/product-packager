import std/os


const
  CACHE_COURSE_CSS_NAME* = "course.css"
  CACHE_COURSE_CSS* = staticRead(".." / "assets" / CACHE_COURSE_CSS_NAME)

  CACHE_GDSCRIPT_DEF_NAME* = "gdscript.xml"
  CACHE_GDSCRIPT_DEF* = staticRead(".." / "assets" / CACHE_GDSCRIPT_DEF_NAME)

  CACHE_GDSCRIPT_THEME_NAME* = "gdscript.theme"
  CACHE_GDSCRIPT_THEME* = staticRead(".." / "assets" / CACHE_GDSCRIPT_THEME_NAME)
