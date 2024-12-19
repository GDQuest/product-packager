import std/[strformat, strutils]

type AppSettingsBuildGDSchool* = ref object
  inputDir*: string
  workingDir*: string
  contentDir*: string
  distDir*: string
  godotProjectDirs*: seq[string]
  ignoreDirs*: seq[string]
  ## If `true`, the script will delete the `distDir` before building the project.
  isCleaning*: bool
  isForced*: bool
  isQuiet*: bool
  isDryRun*: bool
  isShowingMedia*: bool
  ## Prefix to preprend to markdown image urls when making them absolute for GDSchool.
  imagePathPrefix*: string

func `$`*(appSettings: AppSettingsBuildGDSchool): string =
  [
    "AppSettings:", "\tinputDir: {appSettings.inputDir}".fmt,
    "\tworkingDir: {appSettings.workingDir}".fmt,
    "\tcontentDir: {appSettings.contentDir}".fmt,
    "\tdistDir: {appSettings.distDir}".fmt,
    "\tignoreDirs: {appSettings.ignoreDirs.join(\", \")}".fmt,
    "\tgodotProjectDirs: {appSettings.godotProjectDirs.join(\", \")}".fmt,
    "\tisCleaning: {appSettings.isCleaning}".fmt,
    "\tisForced: {appSettings.isForced}".fmt,
  ].join("\n")
