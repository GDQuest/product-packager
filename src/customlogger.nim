import std/
  [ logging
  , terminal
  ]


type CustomLogger = ref object of Logger

func logPrefix(level: Level): tuple[msg: string, color: ForegroundColor] =
  case level
  of lvlAll, lvlDebug: ("DEBUG", fgMagenta)
  of lvlInfo: ("INFO", fgCyan)
  of lvlNotice: ("NOTICE", fgWhite)
  of lvlWarn: ("WARN", fgYellow)
  of lvlError: ("ERROR", fgRed)
  of lvlFatal: ("FATAL", fgRed)
  of lvlNone: ("NONE", fgWhite)

method log(logger: CustomLogger, level: Level, args: varargs[string, `$`]) =
  var f = stdout
  if level >= getLogFilter() and level >= logger.levelThreshold:
    if level >= lvlWarn:
      f = stderr
    let
      ln = substituteLog(logger.fmtStr, level, args)
      prefix = level.logPrefix()
    f.setForegroundColor(prefix.color)
    f.write(prefix.msg)
    f.write(ln)
    f.resetAttributes()
    f.write("\n")
    if level in {lvlError, lvlFatal}: flushFile(f)

proc newCustomLogger(levelThreshold = lvlAll, fmtStr = " "): CustomLogger =
  new result
  result.fmtStr = fmtStr
  result.levelThreshold = levelThreshold


let logger* = newCustomLogger(lvlWarn)
addHandler(logger)
