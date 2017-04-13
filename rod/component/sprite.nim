import nimx.types
import nimx.context
import nimx.image
import nimx.animation
import nimx.property_visitor
import nimx.system_logger

import json, strutils

import rod.rod_types
import rod.node
import rod.ray
import rod.tools.serializer
import rod.component
import rod.utils.image_serialization

#import image_blur

type Sprite* = ref object of Component
    offset*: Point
    size*: Size
    frameOffsets*: seq[Point]
    images*: seq[Image]
    currentFrame*: int
    motionBlurRadius*: float
    segmentsGeometry: seq[float32] # Used for nine-part images

proc image*(s: Sprite): Image =
    if not s.images.isNil and s.images.len > s.currentFrame:
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
    if s.frameOffsets.len > s.currentFrame:
        result += s.frameOffsets[s.currentFrame]

template isNinePart(s: Sprite): bool = not s.segmentsGeometry.isNil
template marginLeft(s: Sprite): float32 = s.segmentsGeometry[0]
template marginRight(s: Sprite): float32 = s.segmentsGeometry[1]
template marginTop(s: Sprite): float32 = s.segmentsGeometry[2]
template marginBottom(s: Sprite): float32 = s.segmentsGeometry[3]

proc calculatedSize(s: Sprite): Size =
    if s.size == zeroSize:
        let i = s.image
        if not i.isNil:
            result = i.size
    else:
        result = s.size

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
        s.currentFrame = int(float(s.images.len - 1) * p)
    s.node.registerAnimation("sprite", a)

method getBBox*(s: Sprite): BBox =
    let sz = s.calculatedSize()
    result.maxPoint = newVector3(sz.width + s.offset.x, sz.height + s.offset.y, 0.01)
    result.minPoint = newVector3(s.offset.x, s.offset.y, 0.0)

method deserialize*(s: Sprite, j: JsonNode, serealizer: Serializer) =
    var v = j{"alpha"} # Deprecated
    if not v.isNil:
        s.node.alpha = v.getFNum(1.0)
        logi "WARNING: Alpha in sprite component deprecated"

    v = j{"images"}
    if v.isNil:
        v = j{"fileNames"}
    if v.isNil:
        s.image = imageWithResource(j["name"].getStr())
        logi "WARNING: Sprite component format deprecated: ", j["name"].getStr()
    else:
        s.images = newSeq[Image](v.len)
        for i in 0 ..< s.images.len:
            s.images[i] = deserializeImage(v[i])

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

method serialize*(c: Sprite, s: Serializer): JsonNode =
    result = newJObject()
    result.add("currentFrame", s.getValue(c.currentFrame))
    result.add("offset", s.getValue(c.offset))

    var imagesNode = newJArray()
    result.add("fileNames", s.getValue(imagesNode))
    for img in c.images:
        imagesNode.add( s.getValue(s.getRelativeResourcePath(img.filePath())) )

method visitProperties*(t: Sprite, p: var PropertyVisitor) =
    p.visitProperty("image", t.image)
    p.visitProperty("curFrame", t.currentFrame)
    p.visitProperty("offset", t.offset)

registerComponent(Sprite)
