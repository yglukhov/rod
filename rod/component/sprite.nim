import nimx / [ types, context, image, animation, property_visitor, system_logger ]
import nimx / assets / asset_manager

import json, strutils

import rod.rod_types
import rod.node
import rod.ray
import rod.tools.serializer
import rod.component

import rod / utils / [ property_desc, serialization_codegen ]

type Sprite* = ref object of Component
    offset*: Point
    size*: Size
    frameOffsets*: seq[Point]
    images*: seq[Image]
    mCurrentFrame*: int16
    segmentsGeometry: seq[float32] # Used for nine-part images
    when not defined(release):
        resourceUrl: string

Sprite.properties:
    images:
        serializationKey: "fileNames"
        combinedWith: frameOffsets

    segmentsGeometry:
        serializationKey: "segments"

template `currentFrame`*(s: Sprite): int =
    int(s.mCurrentFrame)

template `currentFrame=`*(s: Sprite, v: int) =
    # when not defined(release):
    #     assert(v >= 0, s.resourceUrl & " currentFrame negative")
    s.mCurrentFrame = int16(v)

proc image*(s: Sprite): Image =
    if s.images.len > s.currentFrame and s.currentFrame >= 0:
        result = s.images[s.currentFrame]

proc `image=`*(s: Sprite, i: Image) =
    if s.images.isNil:
        s.images = newSeq[Image](1)
    else:
        s.images.setLen(1)
    s.images[0] = i
    s.currentFrame = 0

proc getOffset*(s: Sprite): Point =
    result = s.offset
    if s.frameOffsets.len > s.currentFrame and s.currentFrame >= 0:
        result += s.frameOffsets[s.currentFrame]

template isNinePart(s: Sprite): bool = not s.segmentsGeometry.isNil
template marginLeft(s: Sprite): float32 = s.segmentsGeometry[0]
template marginRight(s: Sprite): float32 = s.segmentsGeometry[1]
template marginTop(s: Sprite): float32 = s.segmentsGeometry[2]
template marginBottom(s: Sprite): float32 = s.segmentsGeometry[3]

proc calculatedSize(s: Sprite): Size =
    ## If size is zeroSize - return image size.
    if s.size == zeroSize:
        let i = s.image
        if not i.isNil:
            result = i.size
    else:
        result = s.size

proc effectiveSize*(s: Sprite): Size =
    result = s.calculatedSize()
    # let off = s.getOffset()

    # result.width += off.x
    # result.height += off.y

method draw*(s: Sprite) =
    let c = currentContext()

    let i = s.image
    if not i.isNil:
        var r: Rect
        r.origin = s.getOffset()
        r.size = s.calculatedSize()
        if s.isNinePart:
            c.drawNinePartImage(i, r, s.marginLeft, s.marginTop, s.marginRight, s.marginBottom)
        else:
            c.drawImage(i, r)

proc createFrameAnimation(s: Sprite) {.inline.} =
    let a = newAnimation()
    const fps = 1.0 / 30.0
    a.loopDuration = float(s.images.len) * fps
    a.continueUntilEndOfLoopOnCancel = true
    a.onAnimate = proc(p: float) =
        s.currentFrame = int16(float(s.images.len - 1) * p)
    s.node.registerAnimation("sprite", a)

method getBBox*(s: Sprite): BBox =
    let sz = s.effectiveSize()
    result.maxPoint = newVector3(sz.width + s.getOffset.x, sz.height + s.getOffset.y, 0.0)
    result.minPoint = newVector3(s.getOffset.x, s.getOffset.y, 0.0)

method deserialize*(s: Sprite, j: JsonNode, serealizer: Serializer) =
    var v = j{"alpha"} # Deprecated
    if not v.isNil:
        s.node.alpha = v.getFNum(1.0)
        logi "WARNING: Alpha in sprite component deprecated"

    when not defined(release):
        s.resourceUrl = serealizer.url

    v = j{"images"}
    if v.isNil:
        v = j{"fileNames"}
    if v.isNil:
        s.image = imageWithResource(j["name"].getStr())
        logi "WARNING: Sprite component format deprecated: ", j["name"].getStr()
    else:
        s.images = newSeq[Image](v.len)
        for i in 0 ..< s.images.len:
            closureScope:
                let ii = i
                deserializeImage(v[ii], serealizer) do(img: Image, err: string):
                    s.images[ii] = img

    v = j{"frameOffsets"}
    if not v.isNil:
        s.frameOffsets = newSeqOfCap[Point](v.len)
        for p in v:
            s.frameOffsets.add(newPoint(p[0].getFNum(), p[1].getFNum()))

    if s.images.len > 1:
        s.createFrameAnimation()

    serealizer.deserializeValue(j, "offset", s.offset)

    v = j{"segments"}
    if not v.isNil and v.len == 4:
        s.segmentsGeometry = newSeq[float32](4)
        for i in 0 ..< 4: s.segmentsGeometry[i] = v[i].getFNum().float32

    v = j{"size"}
    if not v.isNil:
        s.size = newSize(v[0].getFNum(), v[1].getFNum())

proc awake(c: Sprite) =
    if c.images.len > 1:
        c.createFrameAnimation()

genSerializationCodeForComponent(Sprite)

method serialize*(c: Sprite, s: Serializer): JsonNode =
    result = newJObject()
    result.add("currentFrame", s.getValue(c.currentFrame))
    result.add("offset", s.getValue(c.offset))

    var imagesNode = newJArray()
    result.add("fileNames", s.getValue(imagesNode))
    for img in c.images:
        imagesNode.add( s.getValue(s.getRelativeResourcePath(img.filePath())) )

template curFrameAux(t: Sprite): int16 = t.mCurrentFrame
template `curFrameAux=`(t: Sprite, f: int16) = t.mCurrentFrame = f

method visitProperties*(t: Sprite, p: var PropertyVisitor) =
    p.visitProperty("image", t.image)
    p.visitProperty("curFrame", t.curFrameAux)
    p.visitProperty("offset", t.offset)

registerComponent(Sprite)
