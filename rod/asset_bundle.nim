import strutils, ospaths, json, tables, logging, streams
import nimx.assets.abstract_asset_bundle as nab
import nimx / assets / [ url_stream, json_loading, asset_loading, asset_manager, asset_cache ]
import nimx / [ image, types ]
import variant

when not defined(js):
    import os

import rod.utils.bin_deserializer

type AssetBundle* = ref object of nab.AssetBundle
    path*: string
    mBaseUrl: string
    hash*: string
    index*: JsonNode
    spriteSheets*: Table[string, seq[JsonNode]] # Map spritesheet path to all image entries
    binDeserializer*: BinDeserializer

method allAssets(ab: AssetBundle): seq[string] =
    result = @[]
    for k in ab.spriteSheets.keys: result.add(k)
    let files = ab.index{"files"}
    for f in files: result.add(f.str)

proc hasAsset*(ab: AssetBundle, path: string): bool =
    if not ab.binDeserializer.isNil:
        if ab.binDeserializer.hasComposition(path): return true

    # TODO: Everything else

proc realUrlForPath(ab: AssetBundle, path: string): string =
    ab.mBaseUrl / path

method urlForPath*(ab: AssetBundle, path: string): string =
    if path in ab.spriteSheets:
        result = "rod_ss://" & ab.path & '/' & path
    else:
        result = ab.realUrlForPath(path)

proc init(ab: AssetBundle, handler: proc()) {.inline.} =
    # echo "INIT AB: ", ab.mBaseUrl
    let rpPath = ab.mBaseUrl["file://".len .. ^1] / "comps.rodpack"
    # echo "RPPATH: ", rpPath
    var indexComplete = false
    var compsComplete = false

    proc onComplete() =
        if not ab.binDeserializer.isNil:
            ab.binDeserializer.images = ab.index["packedImages"]
        handler()

    openStreamForUrl(ab.mBaseUrl / "comps.rodpack") do(s: Stream, err: string):
        if not s.isNil:
            var ss = s
            when not defined(js):
                if not (s of StringStream):
                    var str = s.readAll()
                    s.close()
                    shallow(str)
                    ss = newStringStream(str)
            echo "Create bindeser: ", ab.mBaseUrl
            ab.binDeserializer = newBinDeserializer(ss)
            ab.binDeserializer.basePath = ab.path

        compsComplete = true
        if indexComplete and compsComplete: onComplete()

    loadJsonFromURL(ab.realUrlForPath("index.rodpack")) do(j: JsonNode):
        ab.index = j
        ab.spriteSheets = initTable[string, seq[JsonNode]]()
        let packedImages = ab.index["packedImages"]
        if not packedImages.isNil:
            if packedImages.kind == JArray:
                for v in packedImages:
                    let fn = v["file"].str
                    if fn in ab.spriteSheets:
                        ab.spriteSheets[fn].add(v)
                    else:
                        ab.spriteSheets[fn] = @[v]
            else:
                for k, v in packedImages:
                    v["orig"] = %k
                    let fn = v["file"].str
                    if fn in ab.spriteSheets:
                        ab.spriteSheets[fn].add(v)
                    else:
                        ab.spriteSheets[fn] = @[v]

        indexComplete = true
        if indexComplete and compsComplete: onComplete()

when defined(js) or defined(emscripten):
    import nimx.pathutils
    type WebAssetBundle* = ref object of AssetBundle
        mBasePath: string

    proc newWebAssetBundle(path, hash: string): WebAssetBundle =
        result.new()
        result.path = path
        result.hash = hash
        let href = parentDir(getCurrentHref())
        if href.find("localhost") != -1 or href.startsWith("file://"):
            result.mBaseUrl = href / "res" / path
        else:
            result.mBaseUrl = href / hash

else:
    import os

    type
        FileAssetBundle* = ref object of AssetBundle
        NativeAssetBundle* = ref object of AssetBundle

    proc newFileAssetBundle(abPath, fileURL: string): FileAssetBundle =
        result.new()
        result.path = abPath
        result.mBaseUrl = fileURL

    proc newNativeAssetBundle(path: string): NativeAssetBundle =
        result.new()
        result.path = path
        when defined(ios):
            result.mBaseUrl = "file://" & getAppDir() / path
        elif defined(macosx):
            result.mBaseUrl = "file://" & getAppDir() /../ "Resources" / path
        else:
            result.mBaseUrl = "file://" & getAppDir() / "res" / path

    when defined(android):
        type AndroidAssetBundle* = ref object of AssetBundle

        proc newAndroidAssetBundle*(path: string): AndroidAssetBundle =
            result.new()
            result.path = path
            result.mBaseUrl = "android_asset://" & path

type AssetBundleDescriptor* = object
    hash*: string
    path*: string
    resources*: seq[string]

proc isConfigRabExternal(configRab: string): bool {.compileTime.} =
    when defined(android):
        configRab.find("androidExternal true") != -1
    else:
        false

proc isConfigRabDebugOnly(configRab: string): bool {.compileTime.} =
    configRab.find("debugOnly true") != -1

proc getEnvCt(k: string): string {.compileTime.} =
    when defined(buildOnWindows): # This should be defined by the naketools.nim
        result = staticExec("cmd /c \"echo %" & k & "%\"")
    else:
        result = staticExec("echo $" & k)
    result.removeSuffix()
    if result == "": result = nil

proc assetBundleDescriptor*(path: static[string]): AssetBundleDescriptor {.compileTime.} =
    const rabFilePath = path / "config.rab"

    const configRab = staticRead(rabFilePath)
    const debugOnly = isConfigRabDebugOnly(configRab)

    when not (defined(release) and debugOnly):
        when defined(js) or defined(emscripten):
            const isExternal = true
        else:
            const isExternal = isConfigRabExternal(configRab)

        when isExternal:
            let prefix = getEnvCt("NIMX_RES_PATH") / path
            let abHash = staticRead(prefix / ".hash")
            result.hash = abHash
        else:
            result.hash = ""

        result.path = path

proc isExternal(abd: AssetBundleDescriptor): bool = abd.hash.len > 0

proc isDownloadable*(abd: AssetBundleDescriptor): bool {.inline.} =
    when defined(js) or defined(emscripten):
        false
    else:
        abd.isExternal

when defined(android):
    import nimx.utils.android
    import android.content.context
    import android.extras.pathutils

proc cacheDir(): string {.inline.} =
    when defined(android):
        mainActivity().getExternalCacheDir().getAbsolutePath()
    else:
        "/tmp/rodappcache"

when not defined(js) and not defined(emscripten) and not defined(windows):
    import os, threadpool, httpclient, net
    import nimx.perform_on_main_thread
    import untar

    type DownloadCtx = ref object
        handler: proc(err: string)
        errorMsg: cstring

    proc onDownloadComplete(ctx: pointer) {.cdecl.} =
        let ctx = cast[DownloadCtx](ctx)
        GC_unref(ctx)
        if ctx.errorMsg.isNil:
            ctx.handler(nil)
        else:
            ctx.handler("Could not download or extract: " & $ctx.errorMsg)
            deallocShared(ctx.errorMsg)

    proc extractGz(zipFileName, destFolder: string): bool =
        var file = newTarFile(zipFileName)
        file.extract(destFolder, tempDir = destFolder / "tmp")
        file.close()
        removeFile(zipFileName)
        result = true

    proc downloadAndUnzip(url, destPath: string, ctx: pointer) =
        let zipFilePath = destPath & ".gz"

        try:
            when defined(ssl):
                when defined(windows) or defined(android):
                    let sslCtx = newContext(verifyMode = CVerifyNone)
                else:
                    let sslCtx = newContext()
                let client = newHttpClient(sslContext = sslCtx)
            else:
                let client = newHttpClient(sslContext = nil)

            client.downloadFile(url, zipFilePath)
            client.close()
            when defined(ssl):
                sslCtx.destroyContext()

            if not extractGz(zipFilePath, destPath):
                raise newException(Exception, "Could not extract")
        except:
            var errorMsg = "Error downloading " & url & " to " & destPath & ": " & getCurrentExceptionMsg()
            let cerrorMsg = cast[cstring](allocShared(errorMsg.len + 1))
            copyMem(cerrorMsg, addr errorMsg[0], errorMsg.len + 1)
            cast[DownloadCtx](ctx).errorMsg = cerrorMsg
            removeDir(destPath)
        finally:
            discard tryRemoveFile(zipFilePath)
            performOnMainThread(onDownloadComplete, ctx)

proc downloadedAssetsDir(abd: AssetBundleDescriptor): string =
    cacheDir() / abd.hash

proc isDownloaded*(abd: AssetBundleDescriptor): bool =
    when not defined(js) and not defined(emscripten):
        if abd.isDownloadable:
            result = dirExists(abd.downloadedAssetsDir)

var getURLForAssetBundle*: proc(hash: string): string

proc downloadAssetBundle*(abd: AssetBundleDescriptor, handler: proc(err: string)) =
    if abd.isDownloadable:
        if abd.isDownloaded:
            handler(nil)
        else:
            when not defined(js) and not defined(emscripten) and not defined(windows) and not defined(rodplugin):
                assert(not getURLForAssetBundle.isNil)
                let url = getURLForAssetBundle(abd.hash)
                var ctx: DownloadCtx
                ctx.new()
                ctx.handler = handler
                GC_ref(ctx)
                spawn downloadAndUnzip(url, abd.downloadedAssetsDir, cast[pointer](ctx))
            else:
                assert(false, "Not supported")
    else:
        handler(nil)

proc newAssetBundle(abd: AssetBundleDescriptor): AssetBundle =
    when defined(js) or defined(emscripten):
        result = newWebAssetBundle(abd.path, abd.hash)
    else:
        if abd.isExternal:
            result = newFileAssetBundle(abd.path, "file://" & abd.downloadedAssetsDir)
        else:
            when defined(android):
                result = newAndroidAssetBundle(abd.path)
            else:
                result = newNativeAssetBundle(abd.path)

proc loadAssetBundle*(abd: AssetBundleDescriptor, handler: proc(mountPath: string, ab: AssetBundle, err: string)) =
    abd.downloadAssetBundle() do(err: string):
        if err.isNil:
            let ab = newAssetBundle(abd)
            ab.init() do():
                handler(abd.path, ab, nil)
        else:
            warn "Asset bundle error for ", abd.hash, " (", abd.path, "): " , err
            handler(abd.path, nil, err)

proc loadAssetBundle*(abd: AssetBundleDescriptor, handler: proc(mountPath: string, ab: AssetBundle)) {.deprecated.}  =
    let newHandler = proc(mountPaths: string, ab: AssetBundle, err: string) =
        if not handler.isNil: handler(mountPaths, ab)

    loadAssetBundle(abd, newHandler)

proc loadAssetBundles*(abds: openarray[AssetBundleDescriptor], handler: proc(mountPaths: openarray[string], abs: openarray[AssetBundle], err: string)) =
    var mountPaths = newSeq[string](abds.len)
    var abs = newSeq[AssetBundle](abds.len)
    let abds = @abds
    var i = 0
    var err: string

    proc load() =
        if i == abds.len:
            handler(mountPaths, abs, nil)
        else:
            abds[i].loadAssetBundle() do(mountPath: string, ab: AssetBundle, err: string):
                if not err.isNil:
                    handler(mountPaths, abs, err)
                else:
                    abs[i] = ab
                    mountPaths[i] = mountPath
                    inc i
                    load()
    load()

proc loadAssetBundles*(abds: openarray[AssetBundleDescriptor], handler: proc(mountPaths: openarray[string], abs: openarray[AssetBundle])) {.deprecated.} =
    let newHandler = proc(mountPaths: openarray[string], abs: openarray[AssetBundle], err: string) =
        if not handler.isNil: handler(mountPaths, abs)

    loadAssetBundles(abds, newHandler)

registerAssetLoader(["rod_ss"], ["png", "jpg", "jpeg", "gif", "tif", "tiff", "tga"]) do(url, path: string, cache: AssetCache, handler: proc()):
    const prefix = "rod_ss://"
    let resPath = url.substr(prefix.len)
    let am = sharedAssetManager()
    let ab = am.assetBundleForPath(resPath)
    if ab of AssetBundle:
        let rab = AssetBundle(ab)
        # let relPath = path.substr(rab.path.len + 1)
        # echo "relPath: ", relPath
        let ssUrl = rab.realUrlForPath(path)
        # echo "ssUrl: ", ssUrl
        loadAsset(ssUrl, path, cache) do():
            let i = cache[path].get(Image)
            for j in rab.spriteSheets[path]:
                let jt = j["tex"]
                let texCoords = [
                    jt[0].getFNum().float32,
                    jt[1].getFNum().float32,
                    jt[2].getFNum().float32,
                    jt[3].getFNum().float32
                ]
                let js = j["size"]
                let sz = newSize(js[0].getFNum(), js[1].getFNum())
                let imagePath = rab.path & '/' & j["orig"].str
                let si: Image = i.subimageWithTexCoords(sz, texCoords)
                si.setFilePath(imagePath)
                am.cacheAsset(imagePath, si)
            handler()
    else:
        raise newException(Exception, "URL is not in rod asset bundle: " & url)
