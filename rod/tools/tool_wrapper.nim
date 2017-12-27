

import os, osproc, strutils

proc rodPluginFile(): string =
    result = getCurrentDir() / "rodplugin.nim"
    if fileExists(result): return
    result = nil

proc nimblePath(package: string): string =
    var (packageDir, err) = execCmdEx("nimble path " & package)
    if err == 0:
        let lines = packageDir.splitLines()
        if lines.len > 1:
            result = lines[^2]

    if result.len == 0:
        raise newException(Exception, "Package " & package & " not found in nimble packages")

proc compileRealBin(bin, toolName, mainNim: string) =
    createDir(bin.parentDir())
    var args = @["c", "--threads:on", "-d:release",
        "--stackTrace:on", "--lineTrace:on",
        "-d:rodplugin",
        "--out:" & bin]
    let plug = rodPluginFile()
    if plug.len != 0:
        args.add("-d:rodPluginFile=" & plug)
        args.add("--path:" & plug.parentDir / "src") # TODO: "src" should be gone
    args.add(nimblePath("rod") / mainNim)
    let nim = findExe("nim")
    echo nim, " ", args.join(" ")
    if startProcess(nim, args = args, options = {poParentStreams}).waitForExit != 0:
        raise newException(Exception, toolName & " compilation failed")

proc runWrapper*(toolName, pathToToolMainNim: string) =
    let tmp = getTempDir()
    let cd = getCurrentDir()
    let projName = splitPath(cd).tail

    let bin = tmp / projName & "_" & toolName & (when defined(windows): ".exe" else: "")
    var needsCompile = not fileExists(bin)
    if needsCompile:
        echo "Compiling ", toolName
        compileRealBin(bin, toolName, pathToToolMainNim)

    # Run the tool
    var args = newSeq[string]()
    for i in 1 .. paramCount():
        args.add(paramStr(i))

    if startProcess(bin, args = args, options = {poParentStreams}).waitForExit != 0:
        raise newException(Exception, toolName & " failed")
