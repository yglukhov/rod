import math

import nimx.types
import nimx.image
import nimx.animation
import nimx.portable_gl

type AnimatedImage* = ref object of Image
    images*: seq[Image]
    currentFrame*: int
    anim*: Animation

proc image*(ai: AnimatedImage): Image =
    if not ai.images.isNil and ai.images.len > ai.currentFrame:
        result = ai.images[ai.currentFrame]

proc `image=`*(ai: AnimatedImage, i: Image) =
    if ai.images.isNil:
        ai.images = newSeq[Image](1)
    else:
        ai.images.setLen(1)
    ai.images[0] = i
    ai.currentFrame = 0

proc newAnimatedImageWithImage*(i: Image): AnimatedImage =
    result.new()
    result.image = i

proc newAnimatedImageWithImageSeq*(imgs: seq[Image]): AnimatedImage =
    result.new()
    if result.images.isNil:
        result.images = newSeq[Image]()
    result.images = imgs

proc frameAnimation*(ai: AnimatedImage, desiredFramerate: int = 30): Animation =
    if ai.anim.isNil:
        if desiredFramerate == 0:
            raise newException(Exception, "Division by zero")
        let a = newAnimation()
        let fps = 1.0 / float(desiredFramerate)
        a.loopDuration = float(ai.images.len) * fps
        a.continueUntilEndOfLoopOnCancel = true
        a.onAnimate = proc(p: float) =
            ai.currentFrame = round(float(ai.images.len - 1) * p).int
        ai.anim = a
    result = ai.anim

method isLoaded*(ai: AnimatedImage): bool =
    if not ai.images.isNil:
        result = ai.images[ai.currentFrame].isLoaded()

method getTextureQuad*(ai: AnimatedImage, gl: GL, texCoords: var array[4, GLfloat]): TextureRef =
    result = getTextureQuad(ai.images[ai.currentFrame], gl, texCoords)

proc size*(ai: AnimatedImage): Size = ai.images[ai.currentFrame].size()
