import nake
import os

proc aeScriptsFolder(): string =
    when defined(windows):
        const searchPaths = [
            "C:/Program Files/Adobe/Adobe After Effects CC 2015.3/Support Files/Scripts",
            "C:/Program Files/Adobe/Adobe After Effects CC 2017/Support Files/Scripts"
        ]
    else:
        const searchPaths = [
            "/Applications/Adobe After Effects CC 2015/Scripts",
            "/Applications/Adobe After Effects CC 2015.3/Scripts",
            "/Applications/Adobe After Effects CC 2017/Scripts"
        ]
    for p in searchPaths:
        if dirExists(p):
            return p

    raise newException(Exception, "Adobe After Effects not found")

task defaultTask, "Build and install":
    direShell nimExe, "js", "--warning[LockLevel]:off", "rod_export.nim"
    direShell nimExe, "js", "--warning[LockLevel]:off", "convert_to_null.nim"
    let scripts = aeScriptsFolder()
    copyFile("nimcache/rod_export.js", scripts / "ScriptUI Panels/rod_export.jsx")
    copyFile("nimcache/convert_to_null.js", scripts / "ScriptUI Panels/convert_to_null.jsx")
