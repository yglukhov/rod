import rod.component
import nimx.types
import nimx.context
import nimx.image
import nimx.animation
import json, strutils

import rod.node
import rod.property_visitor

#import image_blur

type Sprite* = ref object of Component
    offset*: Point
    images*: seq[Image]
    currentFrame*: int
    motionBlurRadius*: float
    prevRootOffset: Vector3

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

method draw*(s: Sprite) =
    let c = currentContext()
    var r: Rect
    r.origin = s.offset

    let i = s.image

    discard """
    if s.motionBlurRadius != 0:
        var n = s.node
        var rootOffset = n.translation
        while not n.isNil:
            rootOffset -= n.translation
            n = n.parent

        if not i.isNil:
            r.size = i.size
            if s.prevRootOffset != [0.Coord, 0, 0]:
                let blurVector = (s.prevRootOffset - rootOffset) * s.motionBlurRadius / 3
                c.drawImageWithBlur(i, r, zeroRect, newVector2(blurVector.x, blurVector.y))
            else:
                c.drawImage(i, r, zeroRect, s.alpha)
        s.prevRootOffset = rootOffset
    el
    """
    if not i.isNil:
        r.size = i.size
        c.drawImage(i, r, zeroRect)

proc createFrameAnimation(s: Sprite) =
    let a = newAnimation()
    const fps = 1.0 / 30.0
    a.loopDuration = float(s.images.len) * fps
    a.continueUntilEndOfLoopOnCancel = true
    a.onAnimate = proc(p: float) =
        s.currentFrame = int(float(s.images.len - 1) * p)
    s.node.registerAnimation("sprite", a)

method deserialize*(s: Sprite, j: JsonNode) =
    var v = j{"alpha"} # Deprecated
    if not v.isNil:
        s.node.alpha = v.getFNum(1.0)

    v = j{"fileNames"}
    if v.isNil:
        s.image = imageWithResource(j["name"].getStr())
    else:
        s.images = newSeq[Image](v.len)
        for i in 0 ..< s.images.len:
            if v[i].kind == JString:
                let name = v[i].getStr()
                if name.endsWith(".sspart"):
                    let parts1 = name.split(" - ")
                    let parts = parts1[1].split('.')
                    let rect = newRect(parts[^5].parseFloat(), parts[^4].parseFloat(), parts[^3].parseFloat(), parts[^2].parseFloat())
                    let realName = parts1[0]
                    let ss = imageWithResource(realName)
                    s.images[i] = ss.subimageWithRect(rect)
                else:
                    s.images[i] = imageWithResource(name)
            else:
                let realName = v[i]["file"].getStr()
                let uv = v[i]["tex"]
                let sz = v[i]["size"]
                let ss = imageWithResource(realName)
                s.images[i] = ss.subimageWithTexCoords(
                                newSize(sz[0].getFNum(), sz[1].getFNum()),
                                [uv[0].getFNum().float32, uv[1].getFNum(), uv[2].getFNum(), uv[3].getFNum()]
                                )

    if s.images.len > 1:
        s.createFrameAnimation()

method visitProperties*(t: Sprite, p: var PropertyVisitor) =
    p.visitProperty("image", t.image)
    p.visitProperty("curFrame", t.currentFrame)

registerComponent[Sprite]()
