import strutils, os


var gResourceWorkingDir = ""
var gFontsWorkingDir = ""

proc setResourceWorkingDir*(dir: string) =
    gResourceWorkingDir = dir
    if gResourceWorkingDir.find("/res/") < 0:
        gResourceWorkingDir = gResourceWorkingDir & "/res/"

    setCurrentDir(gResourceWorkingDir)

proc getResourceWorkingDir*(): string =
    result = gResourceWorkingDir

proc relativeToResourceWorkingDir*(path: string): string =
    let i = path.find(getResourceWorkingDir())
    if i < 0:
        return path
    let l = getResourceWorkingDir().len
    result = path[i+l .. path.high]

proc setFontsWorkingDir*(dir: string) =
    gFontsWorkingDir = dir
proc getFontsWorkingDir*(): string =
    result = gFontsWorkingDir