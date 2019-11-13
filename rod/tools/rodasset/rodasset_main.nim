import os, strutils, times, osproc, logging, macros
import imgtool, asset_cache, migrator
import settings except hash
import json except hash
import sets except hash
import tempfile
import nimx/pathutils

const rodPluginFile {.strdefine.} = ""
when rodPluginFile.len != 0:
    macro doImport(): untyped =
        newTree(nnkImportStmt, newLit(rodPluginFile))
    doImport()

template updateSettingsWithCmdLine() =
    s.graphics.downsampleRatio *= downsampleRatio
    s.graphics.compressToPVR = compressToPVR
    if platform in ["js", "emscripten", "wasm"]:
        s.audio.extension = "mp3"
    else:
        s.audio.extension = "ogg"

proc hash(platform: string = "", downsampleRatio: float = 1.0,
        compressToPVR: bool = false, path: string) =
    let s = parseConfig(path / "config.rab")
    updateSettingsWithCmdLine()
    echo dirHash(path, s)

var gAudioConvTool = ""

proc audioConvTool(): string =
    if gAudioConvTool.len == 0:
        gAudioConvTool = findExe("ffmpeg")
        if gAudioConvTool.len == 0:
            gAudioConvTool = findExe("avconv")
    result = gAudioConvTool

let compressAudio = false

proc convertAudio(fromFile, toFile: string, mp3: bool) =
    var args = @["-i", fromFile, "-y", "-loglevel", "warning"]
    if mp3:
        args.add(["-acodec", "libmp3lame", "-write_xing", "0"])
    else: # ogg
        args.add(["-acodec", "libvorbis"])

    if compressAudio:
        let numChannels = 1
        let sampleRate = 11025
        args.add(["-ac", $numChannels, "-ar", $sampleRate])

    args.add(toFile)
    echo audioConvTool().execProcess(args = args, options={poStdErrToStdOut})

proc copyRemainingAssets(tool: ImgTool, src, dst, audioFmt: string, copiedFiles: var seq[string]) =
    let isMp3 = audioFmt == "mp3"
    for r in walkDirRec(src):
        let sf = r.splitFile()
        if not sf.name.startsWith('.'):
            var reldst = substr(r, src.len + 1)
            let d = dst / reldst
            var doCopy = false
            var doIndex = false
            case sf.ext
            of ".png":
                if unixToNativePath(r) notin tool.processedImages:
                    doCopy = true
            of ".wav", ".mp3", ".ogg":
                createDir(d.parentDir())
                let dest = d.changeFileExt(audioFmt)
                reldst = reldst.changeFileExt(audioFmt)
                doIndex = true
                echo "Converting/compressing audio ", r
                if isMp3:
                    convertAudio(r, dest, true)
                else:
                    convertAudio(r, dest, false)
            of ".json", ".jcomp":
                doIndex = not tool.packCompositions
            of ".rab":
                discard
            else:
                doCopy = true

            if doCopy or doIndex:
                copiedFiles.add(reldst.replace('\\', '/'))

                if doCopy:
                    echo "Copying asset: ", r
                    createDir(d.parentDir())
                    copyFile(r, d)

proc packSingleAssetBundle(s: Settings, cache: string, onlyCache: bool, src, dst: string) =
    let h = dirHash(src, s)
    createDir(cache)
    let c = cache / h
    info "cache: ", c, " for asset bundle: ", src
    if not dirExists(c):
        let tmpCacheDir = mkdtemp(h, "_tmp")
        var tool = newImgTool()

        for f in walkDirRec(src):
            if f.endsWith(".json") or f.endsWith(".jcomp"):
                var tp = f
                normalizePath(tp, false)
                tool.compositionPaths.add(tp)

        tool.noquant = s.graphics.quantizeExceptions
        tool.noposterize = s.graphics.posterizeExceptions
        tool.originalResPath = src
        tool.resPath = tmpCacheDir
        tool.outPrefix = "p"
        tool.compressOutput = s.graphics.compressOutput
        tool.compressToPVR = s.graphics.compressToPVR
        tool.downsampleRatio = s.graphics.downsampleRatio
        tool.extrusion = s.graphics.extrusion
        tool.disablePotAdjustment = s.graphics.disablePotAdjustment
        tool.packUnreferredImages = true
        tool.packCompositions = s.graphics.packCompositions
        let startTime = epochTime()
        tool.run()
        echo "Done. Time: ", epochTime() - startTime

        var copiedFiles = newSeq[string]()
        copyRemainingAssets(tool, src, tmpCacheDir, s.audio.extension, copiedFiles)

        let index = %{
            "packedImages": tool.index,
            "files": %copiedFiles,
        }
        writeFile(tmpCacheDir / "index.rodpack", index.pretty().replace(" \n", "\n"))
        moveDir(tmpCacheDir, c)

    if not onlyCache:
        copyResourcesFromCache(c, h, dst)

iterator assetBundles(resDir: string, fastParse: bool = false): tuple[path: string, ab: Settings] =
    let prefixLen = resDir.len + 1
    for path in walkDirRec(resDir):
        if path.endsWith("config.rab"):
            yield (path.parentDir()[prefixLen .. ^1], parseConfig(path, fastParse))

proc pack(cache: string = "", platform: string = "",
        downsampleRatio: float = 1.0, compressToPVR: bool = false,
        onlyCache: bool = false,
        debug: bool = false,
        src, dst: string) =
    #addHandler(newConsoleLogger()) # Disable logger for now, because nimx provides its own. This will likely be changed.
    let src = expandTilde(src)
    let dst = expandTilde(dst)
    let cache = getCache(cache)
    let rabFile = src / "config.rab"
    if fileExists(rabFile):
        let s = parseConfig(rabFile)
        updateSettingsWithCmdLine()
        packSingleAssetBundle(s, cache, onlyCache, src, dst)
    else:
        for path, s in assetBundles(src):
            if debug or not s.debugOnly:
                updateSettingsWithCmdLine()
                packSingleAssetBundle(s, cache, onlyCache, src & "/" & path, dst & "/" & path)

proc ls(debug: bool = false, androidExternal: bool = false, resDir: string) =
    for path, ab in assetBundles(resDir, true):
        var shouldList = false
        if androidExternal:
            if ab.androidExternal:
                shouldList = true
        elif debug or not ab.debugOnly:
            shouldList = true

        if shouldList: echo path

proc jsonmap(platform: string = "", downsampleRatio: float = 1.0,
        compressToPVR: bool = false, resDir: string, output: string) =
    var j = newJObject()
    for path, s in assetBundles(resDir, true):
        updateSettingsWithCmdLine()
        j[path] = %dirHash(resDir / path, s)
    createDir(output.parentDir())
    writeFile(output, $j)

when isMainModule:
    import cligen
    dispatchMulti([hash], [pack], [upgradeAssetBundle], [ls], [jsonmap])
