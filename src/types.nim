

type AppSettings* = object
  inputDir*: string
  workingDir*: string
  courseDir*: string
  distDir*: string
  godotProjectDirs*: seq[string]
  ignoreDirs*: seq[string]
  pandocExe*: string
  pandocAssetsDir*: string
  isCleaning*: bool
  isForced*: bool
  exec*: seq[string]
