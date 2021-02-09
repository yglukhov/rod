import nimx / [ types, context, image, animation, property_visitor ]
import rod / [rod_types, node, component, tools/serializer]
import rod / utils / [ property_desc, serialization_codegen ]

import json, logging

type Sprite* = ref object of RenderComponent
    offset*: Point
    frameOffsets*: seq[Point]
    images*: seq[Image]
    mCurrentFrame*: int16

Sprite.properties:
    images:
        serializationKey: "fileNames"
        combinedWith: frameOffsets
    mCurrentFrame:
        serializationKey: "currentFrame"
    offset

template `currentFrame`*(s: Sprite): int =
    int(s.mCurrentFrame)

template `currentFrame=`*(s: Sprite, v: int) =
    s.mCurrentFrame = int16(v)

proc image*(s: Sprite): Image =
    if s.images.len > s.currentFrame and s.currentFrame >= 0:
        result = s.images[s.currentFrame]

proc `image=`*(s: Sprite, i: Image) =
    s.images.setLen(1)
    s.images[0] = i
    s.currentFrame = 0

proc getOffset*(s: Sprite): Point =
    result = s.offset
    if s.frameOffsets.len > s.currentFrame and s.currentFrame >= 0:
        result += s.frameOffsets[s.currentFrame]

proc calculatedSize(s: Sprite): Size =
    ## If size is zeroSize - return image size.
    if not s.image.isNil:
        result = s.image.size

proc effectiveSize*(s: Sprite): Size =
    result = s.calculatedSize()

method draw*(s: Sprite) =
    let c = currentContext()

    let i = s.image
    if not i.isNil:
        var r: Rect
        r.origin = s.getOffset()
        r.size = s.calculatedSize()
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

proc awake(c: Sprite) =
    if c.images.len > 1:
        c.createFrameAnimation()

genSerializationCodeForComponent(Sprite)

template curFrameAux(t: Sprite): int16 = t.mCurrentFrame
template `curFrameAux=`(t: Sprite, f: int16) = t.mCurrentFrame = f

method visitProperties*(t: Sprite, p: var PropertyVisitor) =
    p.visitProperty("image", t.image)
    p.visitProperty("curFrame", t.curFrameAux)
    p.visitProperty("offset", t.offset)

registerComponent(Sprite)
