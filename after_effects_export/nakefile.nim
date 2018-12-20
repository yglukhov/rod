import nake
import os

when defined(windows):
    const searchPaths = [
        "C:/Program Files/Adobe/Adobe After Effects CC 2015.3/Support Files/Scripts",
        "C:/Program Files/Adobe/Adobe After Effects CC 2017/Support Files/Scripts",
        "C:/Program Files/Adobe/Adobe After Effects CC 2018/Support Files/Scripts"
    ]
else:
    const searchPaths = [
        "/Applications/Adobe After Effects CC 2015/Scripts",
        "/Applications/Adobe After Effects CC 2015.3/Scripts",
        "/Applications/Adobe After Effects CC 2017/Scripts",
        "/Applications/Adobe After Effects CC 2018/Scripts"
    ]

task defaultTask, "Build and install":
    direShell nimExe, "js", "--warning[LockLevel]:off", "rod_export.nim"
    direShell nimExe, "js", "--warning[LockLevel]:off", "convert_to_null.nim"
    var ok = false
    for sp in searchPaths:
        if dirExists(sp):
            createDir(sp / "ScriptUI Panels")
            copyFile("nimcache/rod_export.js", sp / "ScriptUI Panels/rod_export.jsx")
            copyFile("nimcache/convert_to_null.js", sp / "ScriptUI Panels/convert_to_null.jsx")
            ok = true
    if not ok:
        raise newException(Exception, "After Effect not installed or not found!")