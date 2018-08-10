import os, osproc, json, strutils, times, sequtils, tables, sets, logging
import nimx.pathutils

const multithreaded = compileOption("threads")

when multithreaded:
    import threadpool_simple
    template `^^`[T](e: FlowVar[T]): untyped = ^e
else:
    template sync() = discard
    template spawnX(e: typed): untyped = e

import nimx.types except Point, Size, Rect
import nimx.pathutils

import imgtools / [ imgtools, texcompress, spritesheet_packer ]
import tree_traversal, binformat

type
    ImageOccurenceInfo = object
        parentComposition, parentNode, parentComponent: JsonNode
        frameIndex: int
        textureKey: string
        compPath: string

    ImageOccurence = spritesheet_packer.ImageOccurence[ImageOccurenceInfo]

type ImgTool* = ref object
    compositionPaths*: seq[string]
    compositions: seq[JsonNode]
    outPrefix*: string #
    originalResPath*: string #
    resPath*: string #
    compressOutput*: bool
    compressToPVR*: bool
    downsampleRatio*: float
    disablePotAdjustment*: bool # If true, do not resize images to power of 2
    packUnreferredImages*: bool
    extrusion*: int
    processedImages*: HashSet[string]
    noquant*: seq[string]
    noposterize*: seq[string]
    index*: JsonNode
    packCompositions*: bool

proc newImgTool*(): ImgTool =
    result.new()
    result.downsampleRatio = 1.0
    result.extrusion = 1
    result.compositionPaths = @[]

proc destPath(tool: ImgTool, origPath: string): string =
    let relPath = relativePathToPath(tool.originalResPath, origPath)
    result = tool.resPath / relPath

proc serializedImage(im: ImageOccurence, path: string): JsonNode =
    result = newJObject()
    result["file"] = %path
    let w = im.spriteSheet.size.width.float
    let h = im.spriteSheet.size.height.float
    result["tex"] = %*[(im.dstBounds.x.float + 0.5) / w, (im.dstBounds.y.float + 0.5) / h, ((im.dstBounds.x + im.dstBounds.width).float - 0.5) / w, ((im.dstBounds.y + im.dstBounds.height).float - 0.5) / h]
    result["size"] = %*[im.srcInfo.rect.width, im.srcInfo.rect.height]
    result["off"] = %*[im.srcInfo.rect.x, im.srcInfo.rect.y]

proc pathToPVR(path: string): string {.inline.} =
    result = path.changeFileExt("pvr")

proc adjustImageNode(tool: ImgTool, im: ImageOccurence) =
    # Fixup the fileName node to contain spritesheet filename and texCoords
    var ssPath = im.spriteSheet.path
    if tool.compressToPVR:
        ssPath = ssPath.pathToPVR()

    let result = im.serializedImage(relativePathToPath(tool.destPath(im.info.compPath).parentDir(), ssPath))
    if tool.packCompositions:
        result["orig"] = %relativePathToPath(tool.originalResPath, im.path) #im.path
    doAssert(not im.spriteSheet.isNil)

    if im.info.textureKey.isNil:
        # We are in the sprite component
        im.info.parentComponent["fileNames"].elems[im.info.frameIndex] = result
    else:
        # We are in the mesh component
        im.info.parentComponent[im.info.textureKey]= result

    if im.info.textureKey.isNil:
        # This image occurence is inside a sprite. If image alpha is cropped
        # from top or left we have to adjust frameOffsets in the Sprite node
        if im.srcInfo.rect.x > 0 or im.srcInfo.rect.y > 0:
            var frameOffsets = im.info.parentComponent{"frameOffsets"}
            if frameOffsets.isNil:
                frameOffsets = newJArray()
                for i in 0 ..< im.info.parentComponent["fileNames"].len:
                    frameOffsets.add %*[0, 0]
                im.info.parentComponent["frameOffsets"] = frameOffsets
            frameOffsets.elems[im.info.frameIndex] = %*[im.srcInfo.rect.x, im.srcInfo.rect.y]

proc absImagePath(compPath, imageRelPath: string): string =
    result = compPath.parentDir / imageRelPath
    pathutils.normalizePath(result)

proc checkCompositionRefs(c: JsonNode, compPath, originalResPath: string) =
    var missingRefs = newSeq[string]()
    for n in c.allNodes:
        let jcr = n{"compositionRef"}
        if not jcr.isNil:
            let cr = jcr.str
            let acr = absImagePath(compPath, cr).changeFileExt("")
            if not (fileExists(acr & ".json") or fileExists(acr & ".jcomp")):
                missingRefs.add(acr)
    if missingRefs.len != 0:
        echo "Missing compositionRefs in ", compPath, ":"
        for m in missingRefs:
            echo m
        raise newException(Exception, "Missing compositions")

proc collectImageOccurences(tool: ImgTool): seq[ImageOccurence] {.inline.} =
    result = @[]
    shallow(result)

    var referredImages = initSet[string]()

    for i, c in tool.compositions:
        let compPath = tool.compositionPaths[i]

        checkCompositionRefs(c, compPath, tool.originalResPath)

        template addOccurence(relPath: string, ioinfo: ImageOccurenceInfo, alphaCrop: bool = false) =
            let ap = absImagePath(compPath, relPath)
            referredImages.incl(ap)
            result.add(ImageOccurence(
                path: ap,
                info: ioinfo,
                extrusion: tool.extrusion,
                downsampleRatio: tool.downsampleRatio,
                disablePotAdjustment: tool.disablePotAdjustment,
                allowAlphaCrop: alphaCrop
            ))

        for n, s in c.allSpriteNodes:
            let fileNames = s["fileNames"]
            for ifn in 0 ..< fileNames.len:
                if fileNames[ifn].kind == JString:
                    addOccurence(fileNames[ifn].str, ImageOccurenceInfo(parentComposition: c,
                            parentNode: n, parentComponent: s, frameIndex: ifn,
                            compPath: compPath), true)

        for n, s in c.allMeshComponentNodes:
            for key in ["matcapTextureR", "matcapTextureG", "matcapTextureB",
                "matcapTextureA", "matcapMaskTexture", "albedoTexture",
                "glossTexture", "specularTexture", "normalTexture",
                "bumpTexture", "reflectionTexture", "falloffTexture", "maskTexture"]:

                let t = s{key}
                if not t.isNil and t.kind == JString:
                    addOccurence(t.str, ImageOccurenceInfo(parentComposition: c,
                            parentNode: n, parentComponent: s, textureKey: key,
                            compPath: compPath))

        for n, s in c.allComponentNodesOfType("ParticleSystem"):
            for key in ["texture"]:
                let t = s{key}
                if not t.isNil and t.kind == JString:
                    addOccurence(t.str, ImageOccurenceInfo(parentComposition: c,
                            parentNode: n, parentComponent: s, textureKey: key,
                            compPath: compPath))

    if tool.packUnreferredImages:
        # Collect remaining images that are not referred by anything
        for r in walkDirRec(tool.originalResPath):
            if r.endsWith(".png"):
                let p = unixToNativePath(r)
                if p notin referredImages:
                    result.add(ImageOccurence(
                        path: p,
                        extrusion: tool.extrusion,
                        downsampleRatio: tool.downsampleRatio,
                        disablePotAdjustment: tool.disablePotAdjustment
                    ))

proc createIndex(tool: ImgTool, occurences: openarray[ImageOccurence]) =
    let idx = newJArray()
    for im in occurences:
        var ssPath = im.spriteSheet.path.extractFilename()
        if tool.compressToPVR:
            ssPath = ssPath.pathToPVR()
        let ji = im.serializedImage(ssPath)
        ji["orig"] = %relativePathToPath(tool.originalResPath, im.path)
        idx.add(ji)
#        idx[relativePathToPath(tool.originalResPath, im.path)] = im.serializedImage(ssPath)
    tool.index = idx

proc setCategories(tool: ImgTool, oc: var openarray[ImageOccurence]) =
    for o in oc.mitems:
        let name = splitFile(o.path).name
        let doQuant = not tool.noquant.contains(name)
        let doPosterize = not tool.noposterize.contains(name)

        if doQuant:
            o.category = "quant"
        elif doPosterize:
            o.category = "posterize"
        else:
            o.category = "dont_optimize"

proc convertSpritesheetToPVR(path: string) =
    let dstPath = path.pathToPVR()
    convertToETC2(path, dstPath, false)
    removeFile(path)

proc optimizeSpritesheet(path, category: string) =
    var res = 1
    var qPath = quoteShell(path)

    if category == "quant":
        try:
            let (_, r) = execCmdEx("pngquant --force --speed 1  -o " & qPath & " " & qPath)
            res = r
        except:
            discard
        if res != 0:
            echo "WARNING: pngquant failed ", path
    elif category == "posterize":
        let tmp = path & "__tmp"
        moveFile(path, tmp)
        try:
            let (_, r) = execCmdEx("posterize -Q 90 -b " & quoteShell(tmp) & " " & qPath)
            res = r
        except:
            discard
        if res != 0:
            echo "WARNING: posterize failed or not found ", path
            removeFile(path)
            moveFile(tmp, path)
        else:
            removeFile(tmp)

    # Always run pngcrush
    try:
        # Temp file path is set explicitly to reside near the target file.
        # Otherwise pngcrush will create temp file in current dir and that may
        # cause problems. Originally this bug was observed in docker build image.
        let tmp = quoteShell(path & ".tmp.png")
        let (_, r) = execCmdEx("pngcrush -q -ow -rem allb -noreduce " & qPath & " " & tmp)
        res = r
    except:
        discard
    if res != 0:
        echo "WARNING: removing sRGB failed ", path

proc run*(tool: ImgTool) =
    tool.compositions = newSeq[JsonNode](tool.compositionPaths.len)

    # Parse all compositions
    for i, c in tool.compositionPaths:
        tool.compositions[i] = parseFile(c)

    var occurences = tool.collectImageOccurences()
    tool.setCategories(occurences)

    let packer = newSpriteSheetPacker(tool.resPath & "/" & tool.outPrefix)
    packer.pack(occurences)

    if tool.compressToPVR:
        for ss in packer.spriteSheets:
            spawnX convertSpritesheetToPVR(ss.path)
    else:
        for ss in packer.spriteSheets:
            info "Optimizing ss: ", ss.path
            spawnX optimizeSpritesheet(ss.path, ss.category)

    # Readjust sprite nodes
    for o in occurences:
        if not o.info.parentComposition.isNil:
            tool.adjustImageNode(o)

    tool.processedImages = initSet[string]()
    for o in occurences:
        tool.processedImages.incl(o.path)

    # Write all composisions to single file
    if tool.packCompositions:
        # let allComps = newJObject()
        for i, c in tool.compositions:
            # if "aep_name" in c: c.delete("aep_name")
            var resName = tool.compositionPaths[i]
            if not resName.startsWith("res/"):
                raise newException(Exception, "Wrong composition path: " & resName)
            resName = resName.substr("res/".len)
            # allComps[resName] = c
            tool.compositionPaths[i] = resName
        # var str = ""
        # toUgly(str, allComps)
        # writeFile(tool.resPath & "/" & "comps.jsonpack", str)
    else:
        # Write compositions back to files
        for i, c in tool.compositions:
            let dstPath = tool.destPath(tool.compositionPaths[i])
            createDir(dstPath.parentDir())
            var str = ""
            toUgly(str, c)
            writeFile(dstPath, str)

    tool.createIndex(occurences)

    if tool.packCompositions:
        let b = newBinSerializer()
        b.assetBundlePath = tool.originalResPath.substr("res/".len)
        b.writeCompositions(tool.compositions, tool.compositionPaths, tool.resPath / "comps.rodpack", tool.index)
        echo "Comppack written: ", tool.resPath / "comps.rodpack", " alignment bytes: ", b.totalAlignBytes

    sync() # Wait until spritesheet optimizations complete

proc runImgToolForCompositions*(compositionPatterns: openarray[string], outPrefix: string, compressOutput: bool = true) =
    var tool = newImgTool()

    for p in compositionPatterns:
        for c in walkFiles(p):
            tool.compositionPaths.add(c)

    tool.outPrefix = outPrefix
    tool.compressOutput = compressOutput
    let startTime = epochTime()
    tool.run()
    echo "Done. Time: ", epochTime() - startTime
