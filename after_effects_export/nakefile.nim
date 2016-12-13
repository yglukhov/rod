import nake
import os

when defined(windows):
    let afterEffectsScripts = "C:/Program Files/Adobe/Adobe After Effects CC 2015.3/Support Files/Scripts"
else:
    let afterEffectsScripts = "/Applications/Adobe After Effects CC 2015/Scripts"

task defaultTask, "Build and install":
    direShell nimExe, "js", "--warning[LockLevel]:off", "rod_export.nim"
    direShell nimExe, "js", "--warning[LockLevel]:off", "convert_to_null.nim"
    copyFile("nimcache/rod_export.js", afterEffectsScripts / "ScriptUI Panels/rod_export.jsx")
    copyFile("nimcache/convert_to_null.js", afterEffectsScripts / "ScriptUI Panels/convert_to_null.jsx")
