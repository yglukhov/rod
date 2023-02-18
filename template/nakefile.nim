import nimx/naketools
import osproc, os


const additionalFonts: seq[string] = @[]

proc rodasset(b: Builder, command: string, arguments: varargs[string]) =
    let downsampleRatio = 1
    var args = @["rodasset", command, "--platform=" & b.platform, "--downsampleRatio=" & $downsampleRatio]
    args.add(arguments)
    direShell(args)


beforeBuild = proc(b: Builder) =
    b.mainFile = "main.nim"
    b.originalResourcePath = "res"
    # b.resourcePath = "build"
    b.additionalNimFlags.add(@["--path:res", "--path:src"])


preprocessResources = proc(b: Builder) =
    if b.platform == "ios":
        copyDir(b.originalResourcePath / "ios", b.resourcePath)

    if b.platform == "ios" or b.platform == "ios-sim" or b.platform == "emscripten":
        b.copyResourceAsIs("OpenSans-Regular.ttf")
    for f in additionalFonts:
        b.copyResourceAsIs(f)

    var args = newSeq[string]()
    if b.debugMode:
        args.add("--debug")
    args.add(["--src=" & b.originalResourcePath, "--dst=" & b.resourcePath])
    b.rodasset("pack", args)
