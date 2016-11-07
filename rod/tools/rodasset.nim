import os, strutils, times, tables, osproc
import imgtool, asset_cache

proc hash(audio: string = "ogg", path: string) = echo dirHash(path, audio)

var gAudioConvTool = ""

proc audioConvTool(): string =
    if gAudioConvTool.len == 0:
        gAudioConvTool = findExe("ffmpeg")
        if gAudioConvTool.len == 0:
            gAudioConvTool = findExe("avconv")
    result = gAudioConvTool

proc convertWavToOgg(fromFile, toFile: string) =
    echo audioConvTool().execProcess(
        ["-i", fromFile, "-acodec", "libvorbis", "-y", toFile], options={poStdErrToStdOut})

proc convertWavToMP3(fromFile, toFile: string) =
    var args = @["-i", fromFile, "-acodec", "libmp3lame", "-y"]
    when defined(macosx):
        args.add(["-write_xing", "0"])
    args.add(toFile)
    echo audioConvTool().execProcess(args, options={poStdErrToStdOut})

proc copyRemainingAssets(tool: ImgTool, src, dst, audioFmt: string) =
    let isMp3 = audioFmt == "mp3"
    for r in walkDirRec(src):
        let sf = r.splitFile()
        if not sf.name.startsWith('.'):
            let d = dst / substr(r, src.len)
            var doCopy = false
            case sf.ext
            of ".png":
                if unixToNativePath(r) notin tool.images:
                    doCopy = true
            of ".wav", ".mp3", ".ogg":
                createDir(d.parentDir())
                let ssf = d.splitFile()
                if isMp3 and sf.ext != ".mp3":
                    convertWavToMP3(r, ssf.dir / ssf.name & ".mp3")
                elif sf.ext != ".ogg":
                    convertWavToOgg(r, ssf.dir / ssf.name & ".ogg")
                else:
                    doCopy = true
            of ".json":
                discard
            else:
                doCopy = true

            if doCopy:
                echo "copying remaining asset: ", r, " to ", d
                createDir(d.parentDir())
                copyFile(r, d)

proc pack(cache: string = "", exceptions: string = "", compressToPVR: bool = false, nocompress: bool = false,
        downsampleRatio: float = 1.0, extrusion: int = 1, createIndex: bool = false,
        disablePotAdjustment: bool = false, audio: string = "ogg",
        onlyCache: bool = false,
        src, dst: string) =
    let src = expandTilde(src)
    let dst = expandTilde(dst)
    let cache = getCache(cache)
    let h = dirHash(src, audio)
    let c = cache / h
    echo "rodasset Cache: ", c
    if not dirExists(c):
        let tmpCacheDir = c & ".tmp"
        var tool = newImgTool()

        tool.exceptions = @[]
        for f in walkDirRec(src):
            if f.endsWith(".json"):
                tool.compositionPaths.add(f)
        for e in split(exceptions, ","):
            tool.exceptions.add(e)
        tool.originalResPath = src
        tool.resPath = tmpCacheDir
        createDir(tmpCacheDir)
        tool.outPrefix = "p"
        tool.compressOutput = not nocompress
        tool.compressToPVR = compressToPVR
        tool.downsampleRatio = downsampleRatio
        tool.extrusion = extrusion
        tool.disablePotAdjustment = disablePotAdjustment
        let startTime = epochTime()
        tool.run()
        echo "Done. Time: ", epochTime() - startTime

        copyRemainingAssets(tool, src, tmpCacheDir, audio)
        moveFile(tmpCacheDir, c)

    if not onlyCache:
        copyResourcesFromCache(c, h, dst)

when isMainModule:
    import cligen
    dispatchMulti([hash], [pack])
