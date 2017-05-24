import strutils, ospaths
import nimx.assets.abstract_asset_bundle as nab

type AssetBundle* = ref object of nab.AssetBundle
    path*: string
    hash*: string
    resources*: seq[string]

method init(ab: AssetBundle, handler: proc()) {.base.} =
    handler()

method allAssets(ab: AssetBundle): seq[string] = ab.resources

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
            result.mBasePath = href / "res" / path
        else:
            result.mBasePath = href / hash

    method urlForPath*(ab: WebAssetBundle, path: string): string =
        result = ab.mBasePath / path

else:
    import os

    type
        FileAssetBundle* = ref object of AssetBundle
        NativeAssetBundle* = ref object of AssetBundle
            mBaseUrl: string

    proc newFileAssetBundle(path: string): FileAssetBundle =
        result.new()
        result.path = path

    method urlForPath*(ab: FileAssetBundle, path: string): string =
        result = ab.path / path
        echo "file: ", result

    proc newNativeAssetBundle(path: string): NativeAssetBundle =
        result.new()
        result.path = path
        when defined(macosx):
            result.mBaseUrl = "file://" & getAppDir() /../ "Resources" / path
        elif defined(ios):
            result.mBaseUrl = "file://" & getAppDir() / path
        else:
            result.mBaseUrl = "file://" & getAppDir() / "res" / path

    method urlForPath*(ab: NativeAssetBundle, path: string): string =
        result = ab.mBaseUrl / path

    when defined(android):
        type AndroidAssetBundle* = ref object of AssetBundle
            mBaseUrl: string

        proc newAndroidAssetBundle*(path: string): AndroidAssetBundle =
            result.new()
            result.mBaseUrl = "android_asset://" & path

        method urlForPath*(ab: AndroidAssetBundle, path: string): string =
            return ab.mBaseUrl / path

type AssetBundleDescriptor* = object
    hash*: string
    path*: string
    resources*: seq[string]

proc isConfigRabExternal(configRab: string): bool {.compileTime.} =
    configRab.find("external true") != -1

proc isConfigRabDebugOnly(configRab: string): bool {.compileTime.} =
    configRab.find("debugOnly true") != -1

import nimx.resource_cache

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
        result.resources = getResourceNames(path)
        for i in 0 ..< result.resources.len:
            result.resources[i] = result.resources[i].substr(path.len + 1)

proc isExternal(abd: AssetBundleDescriptor): bool = abd.hash.len > 0

proc isDownloadable*(abd: AssetBundleDescriptor): bool {.inline.} =
    when defined(js) or defined(emscripten):
        false
    else:
        abd.isExternal

proc cacheDir(): string =
    "/tmp/rodappcache"

when not defined(js) and not defined(emscripten):
    import os, threadpool, httpclient, net
    import nimx.perform_on_main_thread
    import zip.zipfiles

    type DownloadCtx = ref object
        handler: proc(err: string)
        success: bool

    proc onDownloadComplete(ctx: pointer) {.cdecl.} =
        let ctx = cast[DownloadCtx](ctx)
        GC_unref(ctx)
        if ctx.success:
            ctx.handler(nil)
        else:
            ctx.handler("Could not download or extract")

    proc extractZip(zipFileName, destFolder: string): bool =
        var z: ZipArchive
        if not z.open(zipFileName):
            return
        z.extractAll(destFolder)
        z.close()
        result = true

    proc downloadAndUnzip(url, destPath: string, ctx: pointer) =
        try:
            when defined(ssl):
                when defined(windows) or defined(android):
                    let sslCtx = newContext(verifyMode = CVerifyNone)
                else:
                    let sslCtx = newContext()
                let client = newHttpClient(sslContext = sslCtx)
            else:
                let client = newHttpClient(sslContext = nil)

            let zipFilePath = destPath & ".zip"

            client.downloadFile(url, zipFilePath)
            client.close()
            when defined(ssl):
                sslCtx.destroyContext()

            cast[DownloadCtx](ctx).success = extractZip(zipFilePath, destPath)
        except:
            discard
        finally:
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
            when not defined(js) and not defined(emscripten):
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
            result = newFileAssetBundle(abd.downloadedAssetsDir)
        else:
            when defined(android):
                result = newAndroidAssetBundle(abd.path)
            else:
                result = newNativeAssetBundle(abd.path)
    result.resources = abd.resources

proc loadAssetBundle*(abd: AssetBundleDescriptor, handler: proc(mountPath: string, ab: AssetBundle)) =
    abd.downloadAssetBundle() do(err: string):
        let ab = newAssetBundle(abd)
        ab.init() do():
            handler(abd.path, ab)

proc loadAssetBundles*(abds: openarray[AssetBundleDescriptor], handler: proc(mountPaths: openarray[string], abs: openarray[AssetBundle])) =
    var mountPaths = newSeq[string](abds.len)
    var abs = newSeq[AssetBundle](abds.len)
    let abds = @abds
    var i = 0

    proc load() =
        if i == abds.len:
            handler(mountPaths, abs)
        else:
            abds[i].loadAssetBundle() do(mountPath: string, ab: AssetBundle):
                abs[i] = ab
                mountPaths[i] = mountPath
                inc i
                load()
    load()
