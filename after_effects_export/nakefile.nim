import nake
import os

when defined(windows):
    let afterEffectsScripts = "C:/Program Files/Adobe/Adobe After Effects CC 2015.3/Support Files/Scripts"
else:
    let afterEffectsScripts = "/Applications/Adobe After Effects CC 2015/Scripts"

task defaultTask, "Build and install":
    direShell nimExe, "js", "--stackTrace:off", "--warning[LockLevel]:off", "rod_export"
    copyFile("nimcache/rod_export.js", afterEffectsScripts / "ScriptUI Panels/rod_export.jsx")
