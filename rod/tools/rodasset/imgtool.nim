import nimPNG
import os, osproc, json, strutils, times, sequtils, tables, algorithm, math, sets

when compileOption("threads"):
    import threadpool

import nimx.rect_packer
import nimx.types except Point, Size, Rect
import nimx.pathutils

import imgtools.imgtools, imgtools.texcompress
import tree_traversal

type Rect = imgtools.Rect
type Point = tuple[x, y: int32]
type Size = tuple[width, height: int]

let consumeLessMemory = defined(windows) or getEnv("CONSUME_LESS_MEMORY") != ""

const isMultithreaded = false and compileOption("threads") # ... not defined(windows)

type
    ImageOccurence = object
        parentComposition, parentNode, parentComponent: JsonNode
        frameIndex: int
        textureKey: string
        compPath: string
        allowAlphaCrop: bool

    SpriteSheetImage = ref object
        spriteSheet: SpriteSheet # Index of sprite sheet in tool.images array
        srcBounds: Rect
        actualBounds: Rect
        originalPath: string
        srcSize: Size
        targetSize: Size
        pos: Point
        png: PNGResult
        occurences: seq[ImageOccurence]
        extrusion: int

    SpriteSheet = ref object
        index: int # Index of sprite sheet in tool.images array
        images: seq[SpriteSheetImage]
        packer: RectPacker
        noquant: bool

proc newSpriteSheetImage(path: string, extrusion: int = 1): SpriteSheetImage =
    result.new()
    result.originalPath = path
    result.occurences = @[]
    result.extrusion = extrusion

proc newSpriteSheet(minSize: Size): SpriteSheet =
    result.new()
    let px = max(nextPowerOfTwo(minSize.width), 1024)
    let py = max(nextPowerOfTwo(minSize.height), 1024)
    result.packer = newPacker(px.int32, py.int32)
    result.packer.maxX = px.int32
    result.packer.maxY = py.int32
    result.images = newSeq[SpriteSheetImage]()

type ImgTool* = ref object
    compositionPaths*: seq[string]
    compositions: seq[JsonNode]
    outPrefix*: string #
    originalResPath*: string #
    resPath*: string #
    compressOutput*: bool
    compressToPVR*: bool
    createIndex*: bool
    downsampleRatio*: float
    disablePotAdjustment*: bool # If true, do not resize images to power of 2
    removeOriginals*: bool
    extrusion*: int
    images*: Table[string, SpriteSheetImage]
    spriteSheets: seq[SpriteSheet]
    exceptions*: seq[string]
    latestOriginalModificationDate: Time


proc newImgTool*(): ImgTool =
    result.new()
    result.images = initTable[string, SpriteSheetImage]()
    result.spriteSheets = @[]
    result.downsampleRatio = 1.0
    result.extrusion = 1
    result.compositionPaths = @[]

proc tryPackImage(ss: SpriteSheet, im: SpriteSheetImage): bool =
    im.pos = ss.packer.packAndGrow(im.targetSize.width.int32 + im.extrusion.int32 * 2, im.targetSize.height.int32 + im.extrusion.int32 * 2)
    result = im.pos.hasSpace
    if result:
        im.pos = (im.pos.x.int32 + im.extrusion.int32, im.pos.y.int32 + im.extrusion.int32)
        ss.images.add(im)
        im.spriteSheet = ss

proc outImgExt(tool: ImgTool): string =
    if tool.compressToPVR:
        result = ".pvr"
    else:
        result = ".png"

proc compressPng(tool: ImgTool, path: string, noquant: bool = false) =
    var res = 1
    var qPath = quoteShell(path)

    if noquant:
        let tmp = path & "__tmp"
        moveFile(path, tmp)
        try:
            res = execCmd("posterize -Q 90 -b " & quoteShell(tmp) & " " & qPath)
        except:
            discard
        if res != 0:
            echo "WARNING: posterize failed or not found ", path
            removeFile(path)
            moveFile(tmp, path)
        else:
            removeFile(tmp)
    else:
        try:
            res = execCmd("pngquant --force --speed 1  -o " & qPath & " " & qPath)
        except:
            discard
        if res != 0:
            echo "WARNING: pngquant failed ", path
    try:
        # Temp file path is set explicitly to reside near the target file.
        # Otherwise pngcrush will create temp file in current dir and that may
        # cause problems. Originally this bug was observed in docker build image.
        let tmp = quoteShell(path & ".tmp.png")
        res = execCmd("pngcrush -ow -rem allb -reduce " & qPath & " " & tmp)
    except:
        discard
    if res != 0:
        echo "WARNING: removing sRGB failed ", path

proc composeAndWrite(tool: ImgTool, ss: SpriteSheet, path: string) =
    var data = newString(ss.packer.width * ss.packer.height * 4)
    for im in ss.images:
        var nullifyWhenDone = false
        var png: PNGResult
        if im.png.isNil:
            png = loadPNG32(im.originalPath)
        else:
            png = im.png
            nullifyWhenDone = true

        if png.data.len == png.width * png.height * 4:
            zeroColorIfZeroAlpha(png.data)
            colorBleed(png.data, png.width, png.height)

        if im.srcSize == im.targetSize:
            blitImage(
                data, ss.packer.width, ss.packer.height, # Target image
                im.pos.x, im.pos.y, # Position in target image
                png.data, png.width, png.height,
                im.srcBounds.x, im.srcBounds.y, im.srcBounds.width, im.srcBounds.height)
        else:
            resizeImage(png.data, png.width, png.height,
                data, ss.packer.width, ss.packer.height,
                im.srcBounds.x, im.srcBounds.y, im.srcBounds.width, im.srcBounds.height,
                im.pos.x, im.pos.y, im.targetSize.width, im.targetSize.height)


        extrudeBorderPixels(
            data,
            ss.packer.width,
            ss.packer.height,
            im.pos.x - im.extrusion,
            im.pos.y - im.extrusion,
            im.targetSize.width + im.extrusion * 2,
            im.targetSize.height + im.extrusion * 2,
            im.extrusion
        )

        if nullifyWhenDone or not isMultithreaded:
            im.png = nil # We no longer need the data in memory

    if tool.compressToPVR:
        let tmpPath = path & ".png"
        discard savePNG32(tmpPath, data, ss.packer.width, ss.packer.height)
        convertToETC2(tmpPath, path, false)
        removeFile(tmpPath)
    else:
        discard savePNG32(path, data, ss.packer.width, ss.packer.height)
        if tool.compressOutput:
            tool.compressPNG(path, ss.noquant)

    if consumeLessMemory:
        GC_fullCollect()

proc destPath(tool: ImgTool, origPath: string): string =
    let relPath = relativePathToPath(tool.originalResPath, origPath)
    result = tool.resPath / relPath

proc serializedImage(im: SpriteSheetImage, path: string): JsonNode =
    result = newJObject()
    result["file"] = %path
    let w = im.spriteSheet.packer.width.float
    let h = im.spriteSheet.packer.height.float
    result["tex"] = %*[(im.pos.x.float + 0.5) / w, (im.pos.y.float + 0.5) / h, ((im.pos.x + im.targetSize.width).float - 0.5) / w, ((im.pos.y + im.targetSize.height).float - 0.5) / h]
    result["size"] = %*[im.srcSize.width, im.srcSize.height]

proc adjustImageNode(tool: ImgTool, im: SpriteSheetImage, o: ImageOccurence) =
    # Fixup the fileName node to contain spritesheet filename and texCoords
    let result = im.serializedImage(relativePathToPath(tool.destPath(o.compPath).parentDir(), tool.resPath / tool.outPrefix & $im.spriteSheet.index & tool.outImgExt))
    doAssert(not im.spriteSheet.isNil)

    if o.textureKey.isNil:
        # We are in the sprite component
        o.parentComponent["fileNames"].elems[o.frameIndex] = result
    else:
        # We are in the mesh component
        o.parentComponent[o.textureKey]= result

    if o.textureKey.isNil:
        # This image occurence is inside a sprite. If image alpha is cropped
        # from top or left we have to adjust frameOffsets in the Sprite node
        if im.srcBounds.x > 0 or im.srcBounds.y > 0:
            var frameOffsets = o.parentComponent{"frameOffsets"}
            if frameOffsets.isNil:
                frameOffsets = newJArray()
                for i in 0 ..< o.parentComponent["fileNames"].len:
                    frameOffsets.add %*[0, 0]
                o.parentComponent["frameOffsets"] = frameOffsets
            frameOffsets.elems[o.frameIndex] = %*[im.srcBounds.x, im.srcBounds.y]

proc recalculateSourceBounds(im: SpriteSheetImage) =
    for o in im.occurences:
        if not o.allowAlphaCrop: return

    im.srcBounds = im.actualBounds
    im.srcSize.width = im.srcBounds.width
    im.srcSize.height = im.srcBounds.height

proc betterDimension(tool: ImgTool, d, e: int): int =
    let r = int(d.float / tool.downsampleRatio)
    if tool.disablePotAdjustment:
        return r
    var changed = true
    result = case r + e * 2
        of 257 .. 400: 256
        of 513 .. 700: 512
        of 1025 .. 1300: 1024
        else:
            changed = false
            r
    if result > 2048: result = 2048
    if changed:
        result -= e * 2

proc recalculateTargetSize(tool: ImgTool, im: SpriteSheetImage) =
    im.targetSize.width = tool.betterDimension(im.srcSize.width, im.extrusion)
    im.targetSize.height = tool.betterDimension(im.srcSize.height, im.extrusion)

proc readFile(im: SpriteSheetImage) =
    let png = loadPNG32(im.originalPath)
    if png.isNil:
        echo "PNG NOT LOADED: ", im.originalPath

    im.actualBounds = imageBounds(png.data, png.width, png.height)

    im.srcBounds.width = png.width
    im.srcBounds.height = png.height
    # im.srcBounds.width = im.actualBounds.x + im.actualBounds.width
    # im.srcBounds.height = im.actualBounds.y + im.actualBounds.height

    if not (consumeLessMemory or isMultithreaded):
        im.png = png

    im.srcSize = (im.srcBounds.width, im.srcBounds.height)
    im.targetSize = im.srcSize

proc updateLastModificationDateWithFile(tool: ImgTool, path: string) =
    let modDate = getLastModificationTime(path)
    if modDate > tool.latestOriginalModificationDate:
        tool.latestOriginalModificationDate = modDate

proc isDirEmpty(d: string): bool =
    result = true
    for k, p in walkDir(d):
        result = false
        break

proc pruneEmptyDir(d: string) =
    var p = d
    while isDirEmpty(p):
        removeDir(p)
        p = p.parentDir()

proc removeLeftoverFiles(tool: ImgTool) =
    for imgPath in tool.images.keys:
        let p = tool.destPath(imgPath)
        removeFile(p)
        pruneEmptyDir(p.parentDir())

proc imageAtPath(tool: ImgTool, compPath, imageRelPath: string): SpriteSheetImage {.inline.} =
    var absPath = compPath.parentDir / imageRelPath
    absPath.normalizePath()

    result = tool.images.getOrDefault(absPath)
    if result.isNil:
        if not fileExists(absPath):
            echo "Error: file not found: ", absPath, " (reffered from ", compPath, ")"
        result = newSpriteSheetImage(absPath, tool.extrusion)
        tool.updateLastModificationDateWithFile(absPath)
        tool.images[absPath] = result

proc collectImageOccurences(tool: ImgTool) {.inline.} =
    for i, c in tool.compositions:
        let compPath = tool.compositionPaths[i]

        for n, s in c.allSpriteNodes:
            let fileNames = s["fileNames"]
            for ifn in 0 ..< fileNames.len:
                if fileNames[ifn].kind == JString:
                    var im = tool.imageAtPath(compPath, fileNames[ifn].str)
                    im.occurences.add ImageOccurence(parentComposition: c,
                            parentNode: n, parentComponent: s, frameIndex: ifn,
                            compPath: compPath,
                            allowAlphaCrop: true)

        for n, s in c.allMeshComponentNodes:
            for key in ["matcapTextureR", "matcapTextureG", "matcapTextureB",
                "matcapTextureA", "matcapMaskTexture", "albedoTexture",
                "glossTexture", "specularTexture", "normalTexture",
                "bumpTexture", "reflectionTexture", "falloffTexture", "maskTexture"]:

                let t = s{key}
                if not t.isNil and t.kind == JString:
                    var im = tool.imageAtPath(compPath, t.str)
                    im.occurences.add(ImageOccurence(parentComposition: c,
                            parentNode: n, parentComponent: s, textureKey: key,
                            compPath: compPath))

        for n, s in c.allComponentNodesOfType("ParticleSystem"):
            for key in ["texture"]:
                let t = s{key}
                if not t.isNil and t.kind == JString:
                    var im = tool.imageAtPath(compPath, t.str)
                    im.occurences.add(ImageOccurence(parentComposition: c,
                            parentNode: n, parentComponent: s, textureKey: key,
                            compPath: compPath))

proc writeIndex(tool: ImgTool) =
    let root = newJObject()
    let packedImages = newJObject()
    root["packedImages"] = packedImages
    for im in tool.images.values:
        packedImages[relativePathToPath(tool.originalResPath, im.originalPath)] = im.serializedImage(tool.outPrefix & $im.spriteSheet.index & tool.outImgExt)
    writeFile(parentDir(tool.resPath / tool.outPrefix) & "index.rodpack", root.pretty().replace(" \n", "\n"))
    echo root.pretty().replace(" \n", "\n")

proc packImagesToSpritesheets(tool: ImgTool, images: openarray[SpriteSheetImage], spritesheets: var seq[SpriteSheet], offset: int = 0, noquant: bool = false) =
    for i, im in images:
        var done = false
        for ss in spritesheets:
            done = ss.tryPackImage(im)
            if done: break
        if not done:
            let newSS = newSpriteSheet((im.targetSize.width + im.extrusion * 2, im.targetSize.height + im.extrusion))
            done = newSS.tryPackImage(im)
            if done:
                newSS.index = spritesheets.len + offset
                newSS.noquant = noquant
                spritesheets.add(newSS)
            else:
                echo "Could not pack image: ", im.originalPath

proc assignImagesToSpriteSheets(tool: ImgTool) =
    # Allocate spritesheets for images
    # Here we try two approaches of packing. The first is to sort images
    # by max(w, h). The second is to sort by area.

    var allImages: seq[SpriteSheetImage] = @[]
    var exceptionImages: seq[SpriteSheetImage] = @[]

    if tool.exceptions.len > 0:
        for k, v in tool.images:
            var name = splitFile(k).name
            if tool.exceptions.contains(name):
                exceptionImages.add(v)
            else:
                allImages.add(v)
    else:
        allImages = toSeq(values(tool.images))

    proc assign(imgs: var seq[SpriteSheetImage]) =
        var try1 = newSeq[SpriteSheet]()
        var try2 = newSeq[SpriteSheet]()

        # First approach
        imgs.sort do(x, y: SpriteSheetImage) -> int:
            max(y.targetSize.width, y.targetSize.height) - max(x.targetSize.width, x.targetSize.height)
        tool.packImagesToSpritesheets(imgs, try1)

        # Second approach
        imgs.sort do(x, y: SpriteSheetImage) -> int:
            y.targetSize.width * y.targetSize.height - x.targetSize.width * x.targetSize.height
        tool.packImagesToSpritesheets(imgs, try2)

        # Choose better approach
        if try1.len < try2.len:
            # Redo try1 again
            imgs.sort do(x, y: SpriteSheetImage) -> int:
                max(y.targetSize.width, y.targetSize.height) - max(x.targetSize.width, x.targetSize.height)
            try1.setLen(0)
            tool.packImagesToSpritesheets(imgs, try1)
            shallowCopy(tool.spriteSheets, try1)
        else:
            shallowCopy(tool.spriteSheets, try2)
    assign(allImages)
    if tool.exceptions.len > 0:
        var try3 = newSeq[SpriteSheet]()
        tool.packImagesToSpritesheets(exceptionImages, try3, tool.spriteSheets.len, true)
        tool.spriteSheets.add(try3)

when isMultithreaded:
    proc composeAndWriteAux(tool, ss: pointer, path: string) =
        let tool = cast[ImgTool](tool)
        let ss = cast[SpriteSheet](ss)
        tool.composeAndWrite(ss, path)

proc readImageFileAux(tool, im: pointer) {.inline.} =
    let i = cast[SpriteSheetImage](im)
    let tool = cast[ImgTool](tool)
    i.readFile()
    if consumeLessMemory:
        GC_fullCollect()
    i.recalculateSourceBounds()
    tool.recalculateTargetSize(i)

proc run*(tool: ImgTool) =
    tool.compositions = newSeq[JsonNode](tool.compositionPaths.len)

    # Parse all compositions
    for i, c in tool.compositionPaths:
        tool.updateLastModificationDateWithFile(c)
        tool.compositions[i] = parseFile(c)

    tool.collectImageOccurences()

    # Check if destination files are newer than original files. If yes, we
    # don't need to do anything.
    var needsUpdate = not fileExists(tool.resPath / tool.outPrefix & "0" & tool.outImgExt)
    if not needsUpdate:
        for c in tool.compositionPaths:
            let dstPath = tool.destPath(c)
            if not fileExists(dstPath) or getLastModificationTime(dstPath) <= tool.latestOriginalModificationDate:
                needsUpdate = true
                break

    if needsUpdate:
        for i in tool.images.values:
            echo "Reading file: ", i.originalPath
            when isMultithreaded:
                if consumeLessMemory:
                    spawn readImageFileAux(cast[pointer](tool), cast[pointer](i))
                else:
                    readImageFileAux(cast[pointer](tool), cast[pointer](i))
            else:
                readImageFileAux(cast[pointer](tool), cast[pointer](i))

        when isMultithreaded: sync() # Wait for all spawned tasks

        if consumeLessMemory:
            GC_fullCollect()

        tool.assignImagesToSpriteSheets()

        # Blit images to spriteSheets and save them
        for i, ss in tool.spriteSheets:
            echo "Saving ", i + 1, " of ", tool.spriteSheets.len
            for v in ss.images:
                echo "    - image ", v.originalPath
            when isMultithreaded:
                spawn composeAndWriteAux(cast[pointer](tool), cast[pointer](ss), tool.resPath / tool.outPrefix & $i & tool.outImgExt)
            else:
                tool.composeAndWrite(ss, tool.resPath / tool.outPrefix & $i & tool.outImgExt)

        when isMultithreaded: sync() # Wait for all spawned tasks

        # Readjust sprite nodes
        for im in tool.images.values:
            for o in im.occurences:
                tool.adjustImageNode(im, o)

        let packCompositions = false

        # Write all composisions to single file
        if packCompositions:
            let allComps = newJObject()
            for i, c in tool.compositions:
                if "aep_name" in c: c.delete("aep_name")
                var resName = tool.compositionPaths[i]
                if not resName.startsWith("res/"):
                    raise newException(Exception, "WRONG COMPOSITION PATH: " & resName)
                resName = resName.substr("res/".len)
                allComps[resName] = c
            var str = ""
            toUgly(str, allComps)
            writeFile(tool.resPath / "comps.jsonpack", str)
        else:
            # Write compositions back to files
            for i, c in tool.compositions:
                let dstPath = tool.destPath(tool.compositionPaths[i])
                createDir(dstPath.parentDir())
                writeFile(dstPath, c.pretty().replace(" \n", "\n"))

        if tool.createIndex:
            tool.writeIndex()
    else:
        echo "Everyting up to date"
    if tool.removeOriginals:
        tool.removeLeftoverFiles()

proc runImgToolForCompositions*(compositionPatterns: openarray[string], outPrefix: string, compressOutput: bool = true) =
    var tool = newImgTool()

    for p in compositionPatterns:
        for c in walkFiles(p):
            tool.compositionPaths.add(c)

    tool.outPrefix = outPrefix
    tool.compressOutput = compressOutput
    tool.removeOriginals = true
    let startTime = epochTime()
    tool.run()
    echo "Done. Time: ", epochTime() - startTime
