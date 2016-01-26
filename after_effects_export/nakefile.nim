import nake
import os

let afterEffectsScripts = "/Applications/Adobe After Effects CC 2015/Scripts"

task defaultTask, "Build and install":
    direShell nimExe, "js", "--stackTrace:off", "--warning[LockLevel]:off", "rod_export"
    copyFile("nimcache/rod_export.js", afterEffectsScripts / "ScriptUI Panels/rod_export.jsx")
