import os, osproc, strutils

proc rodPluginFile(): string =
    result = getCurrentDir() / "rodplugin.nim"
    if fileExists(result): return
    result = ""

proc nimblePath(package: string): string =
    var (packageDir, err) = execCmdEx("nimble path " & package)
    if err == 0:
        let lines = packageDir.splitLines()
        if lines.len > 1:
            result = lines[^2]

    if result.len == 0:
        raise newException(Exception, "Package " & package & " not found in nimble packages")

proc getRodPackagePath(): string =
    result = nimblePath("rod")
    if fileExists("nimble.paths"):
        echo "tring nimble.paths"
        # --path:"/Users/bro/.nimble/pkgs2/opengl-1.2.9-87ece9f3a9f99d17332b50885e15a4dcb18c51b5"
        for line in lines("nimble.paths"):
            if line.startsWith("--path"):
                let pathOverride = line[8 .. ^2]
                echo "tring pathOverride: ", pathOverride, " exist ", fileExists(pathOverride / "rod.nimble")
                if fileExists(pathOverride / "rod.nimble"):
                    return pathOverride
    if fileExists("rod.nimble"):
        echo "seems like we run from rod dir itself"
        result = getCurrentDir()

proc compileRealBin(bin, toolName, mainNim: string, useDanger: bool,  cflags: seq[string]) =
    createDir(bin.parentDir())
    # echo "rodasset compiles from directory: ", bin.parentDir()
    var args = @["c", "--threads:on", "-d:release",
        "-d:rodplugin", "--warning[LockLevel]:off", "--mm:refc"]
    if useDanger:
        args.add(@["-d:danger" ])
    else:
        args.add(@["--stackTrace:on", "--lineTrace:on"])

    args.add(cflags)
    args.add("--out:" & bin)
    let plug = rodPluginFile()
    if plug.len != 0:
        args.add("-d:rodPluginFile=" & plug)
        args.add("--path:" & plug.parentDir / "src") # TODO: "src" should be gone
    args.add("--path:" & getRodPackagePath())
    args.add(getRodPackagePath() / mainNim)
    let nim = findExe("nim")
    echo nim, " ", args.join(" ")
    if startProcess(nim, args = args, options = {poParentStreams}).waitForExit != 0:
        raise newException(Exception, toolName & " compilation failed")

proc wrapperAUX(bin, toolName, pathToToolMainNim: string, useDanger:bool, cflags: seq[string] = @[]) =
    var needsCompile = not fileExists(bin)
    var passArgs = newSeq[string]()

    for i in 1 .. paramCount():
        let p = paramStr(i)
        if p == "--recompile":
            needsCompile = true
        else:
            passArgs.add(p)

    if needsCompile:
        echo "Compiling ", toolName
        compileRealBin(bin, toolName, pathToToolMainNim, useDanger, cflags)

    # Run the tool
    if startProcess(bin, args = passArgs, options = {poParentStreams}).waitForExit != 0:
        raise newException(Exception, toolName & " failed")


proc runWrapper*(toolName, pathToToolMainNim: string) =
    var prefix = getEnv("ROD_ASSET_BIN")
    if prefix.len == 0:
        prefix = getTempDir()
    let cd = getCurrentDir()
    echo "cur dir ", cd
    let projName = splitPath(cd).tail
    let bin = prefix / projName & "_" & toolName & (when defined(windows): ".exe" else: "")
    wrapperAUX(bin, toolName, pathToToolMainNim, useDanger = true)

proc runEditorWrapper*(toolName, pathToToolMainNim: string) =
    let cd = getCurrentDir()
    let bin = cd / splitPath(cd).tail & "_" & toolName & (when defined(windows): ".exe" else: "")
    wrapperAUX(bin, toolName, pathToToolMainNim, useDanger = false, @["-d:rodedit"])
