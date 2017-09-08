# This is a wrapper to rodasset_main. It compiles rodasset_main with rod
# plugins of the project that calls the wrapper.

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

proc compileRealBin(bin: string) =
    createDir(bin.parentDir())
    var args = @[findExe("nim"), "c", "--threads:on", "-d:release", "--stackTrace:on", "--lineTrace:on", "--out:" & bin]
    let plug = rodPluginFile()
    if plug.len != 0:
        args.add("-d:rodPluginFile=" & plug)
    args.add(nimblePath("rod") / "rod/tools/rodasset/rodasset_main.nim")
    echo args.join(" ")
    let res = execCmd(args.join(" "))
    if res != 0:
        raise newException(Exception, "rodasset compilation failed")

proc main() =
    let tmp = getTempDir()
    let cd = getCurrentDir()
    let projName = splitPath(cd).tail

    let bin = tmp / projName & "_rodasset"

    var needsCompile = not fileExists(bin)
    if needsCompile:
        echo "Compiling rodasset"
        compileRealBin(bin)

    # Run the tool
    var args = @[bin]
    for i in 1 .. paramCount():
        args.add(paramStr(i))
    if execCmd(args.join(" ")) != 0:
        raise newException(Exception, "Rodasset failed")

main()
