import os, strutils, times, osproc, sets, logging, macros
import imgtool, asset_cache, migrator
import settings except hash
import json except hash
import tempfile
import nimx.pathutils

const rodPluginFile {.strdefine.} = ""
when rodPluginFile.len != 0:
    macro doImport(): untyped =
        newNimNode(nnkImportStmt).add(newLit(rodPluginFile))
    doImport()

template settingsWithCmdLine(): Settings =
    let s = newSettings()
    s.audio.extension = audio
    s.graphics.downsampleRatio = downsampleRatio
    s.graphics.compressOutput = not nocompress
    s.graphics.extrusion = extrusion
    s.graphics.disablePotAdjustment = disablePotAdjustment
    s.graphics.packCompositions = packCompositions
    s.graphics.compressToPVR = compressToPVR
    s.graphics.quantizeExceptions = exceptions & "," & noquant
    s.graphics.posterizeExceptions = noposterize
    s

proc hash(audio: string = "ogg", downsampleRatio: float = 1.0, nocompress: bool = false,
    compressToPVR: bool = false, extrusion: int = 1, disablePotAdjustment: bool = false,
    packCompositions: bool = false,
    exceptions: string = "", noposterize: string = "", noquant: string = "",
    path: string) =
    let s = settingsWithCmdLine()
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
    echo audioConvTool().execProcess(args, options={poStdErrToStdOut})

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
            of ".json":
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

proc pack(cache: string = "", exceptions: string = "", noposterize: string = "", noquant: string = "", compressToPVR: bool = false, nocompress: bool = false,
        downsampleRatio: float = 1.0, extrusion: int = 1, createIndex: bool = false,
        disablePotAdjustment: bool = false, audio: string = "ogg", packCompositions: bool = false,
        onlyCache: bool = false,
        src, dst: string) =
    addHandler(newConsoleLogger())
    let src = expandTilde(src)
    let dst = expandTilde(dst)
    let cache = getCache(cache)
    let s = settingsWithCmdLine()
    let h = dirHash(src, s)
    createDir(cache)
    let c = cache / h
    echo "rodasset Cache: ", c
    if not dirExists(c):
        let tmpCacheDir = mkdtemp(h, "_tmp")
        var tool = newImgTool()

        tool.noquant = @[]
        tool.noposterize = @[]
        for f in walkDirRec(src):
            if f.endsWith(".json"):
                var tp = f
                normalizePath(tp, false)
                tool.compositionPaths.add(tp)
                
        for e in split(exceptions, ","): tool.noquant.add(e)
        for e in split(noquant, ","): tool.noquant.add(e)
        for e in split(noposterize, ","): tool.noposterize.add(e)
        tool.originalResPath = src
        tool.resPath = tmpCacheDir
        tool.outPrefix = "p"
        tool.compressOutput = not nocompress
        tool.compressToPVR = compressToPVR
        tool.downsampleRatio = downsampleRatio
        tool.extrusion = extrusion
        tool.disablePotAdjustment = disablePotAdjustment
        tool.packUnreferredImages = true
        tool.packCompositions = packCompositions
        let startTime = epochTime()
        tool.run()
        echo "Done. Time: ", epochTime() - startTime

        var copiedFiles = newSeq[string]()
        copyRemainingAssets(tool, src, tmpCacheDir, audio, copiedFiles)

        let index = %{
            "packedImages": tool.index,
            "files": %copiedFiles,
        }
        writeFile(tmpCacheDir / "index.rodpack", index.pretty().replace(" \n", "\n"))

        when declared(moveDir):
            moveDir(tmpCacheDir, c) # Newer nim should support it
        else:
            moveFile(tmpCacheDir, c)

    if not onlyCache:
        copyResourcesFromCache(c, h, dst)

when isMainModule:
    import cligen
    dispatchMulti([hash], [pack], [upgradeAssetBundle])
