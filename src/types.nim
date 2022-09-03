import std/
  [ strformat
  , strutils
  ]
import md/
  [ utils
  ]


type
  AppSettingsFormat* = object
    inputFiles*: seq[string]
    inPlace*: bool
    outputDir*: string

  AppSettingsBuildCourse* = object
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

  AppSettingsBuildGDSchool* = object
    inputDir*: string
    workingDir*: string
    courseDir*: string
    distDir*: string
    godotProjectDirs*: seq[string]
    ignoreDirs*: seq[string]
    isCleaning*: bool
    isForced*: bool


func `$`*(appSettings: AppSettingsFormat): string =
  [ "AppSettings:"
  , "\tinputFiles: {appSettings.inputFiles}".fmt
  , "\tinPlace: {appSettings.inPlace}".fmt
  , "\toutputDir: {appSettings.outputDir}".fmt
  ].join(NL)


func `$`*(appSettings: AppSettingsBuildCourse): string =
  [ "AppSettings:"
  , "\tinputDir: {appSettings.inputDir}".fmt
  , "\tworkingDir: {appSettings.workingDir}".fmt
  , "\tcourseDir: {appSettings.courseDir}".fmt
  , "\tdistDir: {appSettings.distDir}".fmt
  , "\tgodotProjectDirs: {appSettings.godotProjectDirs}".fmt
  , "\tignoreDirs: {appSettings.ignoreDirs.join(\", \")}".fmt
  , "\tpandocExe: {appSettings.pandocExe}".fmt
  , "\tpandocAssetsDir: {appSettings.pandocAssetsDir}".fmt
  , "\tisCleaning: {appSettings.isCleaning}".fmt
  , "\tisForced: {appSettings.isForced}".fmt
  , "\texec: {appSettings.exec}".fmt
  ].join(NL)


func `$`*(appSettings: AppSettingsBuildGDSchool): string =
  [ "AppSettings:"
  , "\tinputDir: {appSettings.inputDir}".fmt
  , "\tworkingDir: {appSettings.workingDir}".fmt
  , "\tcourseDir: {appSettings.courseDir}".fmt
  , "\tdistDir: {appSettings.distDir}".fmt
  , "\tgodotProjectDirs: {appSettings.godotProjectDirs}".fmt
  , "\tignoreDirs: {appSettings.ignoreDirs.join(\", \")}".fmt
  , "\tisCleaning: {appSettings.isCleaning}".fmt
  , "\tisForced: {appSettings.isForced}".fmt
  ].join(NL)
