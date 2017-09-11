import json
import tables
import math

import nimx.types
import nimx.context
import nimx.image
import nimx.view
import nimx.matrixes
import nimx.composition
import nimx.property_visitor
import nimx.system_logger
import nimx.portable_gl

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod / utils / [ property_desc, serialization_codegen ]
import rod.component
import rod.component.sprite
import rod.component.solid
import rod.component.camera
import rod.viewport

const comonPrefix = """
(sampler2D mask_img, vec4 mask_img_coords, vec4 mask_bounds, mat4 mvp_inv, float msk_alpha) {

    vec2 mskVpos = vec4(mvp_inv * vec4(gl_FragCoord.x, gl_FragCoord.y, 0.0, 1.0)).xy;
    vec2 destuv = ( mskVpos - mask_bounds.xy ) / mask_bounds.zw;
    vec2 uv = mask_img_coords.xy + (mask_img_coords.zw - mask_img_coords.xy) * destuv;

    vec4 mask_color = texture2D(mask_img, uv);

    float rect_alpha = 1.0;
    if (uv.x < mask_img_coords.x || uv.x > mask_img_coords.z || uv.y < mask_img_coords.y || uv.y > mask_img_coords.w) {
        rect_alpha = 0.0;
    }
"""
const alphaPostfix = """
    float mask_alpha = mask_color.a * rect_alpha * msk_alpha;
    gl_FragColor.a *= mask_alpha;
}
"""
const alphaInvertedPostfix = """
    float mask_alpha = mask_color.a * rect_alpha * msk_alpha;
    mask_alpha = 1.0 - clamp(mask_alpha, 0.0, 1.0);
    gl_FragColor.a *= mask_alpha;
}
"""
const lumaPostfix = """
    float luma = dot(mask_color.rgb, vec3(0.299, 0.587, 0.114));
    float mask_alpha = luma * mask_color.a * rect_alpha * msk_alpha;
    gl_FragColor.a *= mask_alpha;
}
"""
const lumaInvertedPostfix = """
    float luma = dot(mask_color.rgb, vec3(0.299, 0.587, 0.114));
    float mask_alpha = luma * mask_color.a * rect_alpha * msk_alpha;
    mask_alpha = 1.0 - clamp(mask_alpha, 0.0, 1.0);
    gl_FragColor.a *= mask_alpha;
}
"""

template maskPost(name, src: string): PostEffect =
    newPostEffect("void " & name & src, name, ["sampler2D", "vec4", "vec4", "mat4", "float"])

var effect = [
    maskPost("maskAlphaEffect", comonPrefix & alphaPostfix), # tmAlpha
    maskPost("maskAlphaInvertedEffect", comonPrefix & alphaInvertedPostfix), # tmAlphaInverted
    maskPost("maskLumaEffect", comonPrefix & lumaPostfix), # tmLuma
    maskPost("maskLumaInvertedEffect", comonPrefix & lumaInvertedPostfix) # tmLumaInverted
]

type MaskType* = enum
    tmNone, tmAlpha, tmAlphaInverted, tmLuma, tmLumaInverted

type Mask* = ref object of Component
    maskType*: MaskType
    mMaskNode: Node
    maskSprite*: Sprite
    mWithRTI: bool

Mask.properties:
    maskType
    layerName:
        phantom: string

proc findComponents*(n: Node, T: typedesc[Component]): auto =
    type TT = T
    var compSeq = newSeq[TT]()

    discard n.findNode do(nd: Node) -> bool:
        let comp = nd.componentIfAvailable(TT)
        if not comp.isNil: compSeq.add(comp)
    return compSeq

proc setupMaskComponent(msk: Mask)
proc trySetupMask(msk: Mask)

template maskNode*(msk: Mask): Node = msk.mMaskNode
template `maskNode=`*(msk: Mask, val: Node) =
    msk.mMaskNode = val
    trySetupMask(msk)

proc setupMaskComponent(msk: Mask) =
    if not msk.maskNode.isNil:
        let spriteCmps = msk.maskNode.findComponents(Sprite)
        let solidCmps = msk.maskNode.findComponents(Solid)
        if spriteCmps.len > 1 or solidCmps.len > 0:
            msk.mWithRTI = true
            # TODO
            # if solidCmps.len == 1 and spriteCmps.len == 0: # do solid RTI
            # else: # do all branch RTI
            raise newException(Exception, "RTI not implemented")
        elif spriteCmps.len == 1:
            msk.maskSprite = spriteCmps[0]
        else:
            msk.maskSprite = nil

proc trySetupMask(msk: Mask) =
    try: msk.setupMaskComponent()
    except Exception:
        let ex = getCurrentException()
        logi ex.name, ": ", getCurrentExceptionMsg(), "\n", ex.getStackTrace()

method componentNodeWasAddedToSceneView*(msk: Mask) =
    if msk.maskSprite.isNil:
        msk.trySetupMask()

method componentNodeWillBeRemovedFromSceneView*(msk: Mask) =
    msk.maskSprite = nil

template inv(m: Matrix4): Matrix4 =
    var res: Matrix4
    if not m.tryInverse(res):
        res.loadIdentity()
    res

const clipMat: Matrix4 = [0.5.Coord,0,0,0,0,0.5,0,0,0,0,1.0,0,0.5,0.5,0,1.0]

method beforeDraw*(msk: Mask, index: int): bool =
    if not msk.maskSprite.isNil and not msk.maskSprite.image.isNil and msk.maskType != tmNone:

        if msk.mWithRTI:
            # TODO RTI
            discard

        let vp = msk.node.sceneView
        var theQuad {.noinit.}: array[4, GLfloat]
        let tex = getTextureQuad(msk.maskSprite.image, currentContext().gl, theQuad)
        let maskImgCoords = newRect(theQuad[0], theQuad[1], theQuad[2], theQuad[3])
        let maskBounds = newRect(msk.maskSprite.getOffset(), msk.maskSprite.image.size)
        var trInv = (clipMat * vp.viewProjMatrix * msk.maskSprite.node.worldTransform()).inv()
        let glvp = currentContext().gl.getViewport()
        trInv.scale(newVector3(1.0/(glvp[2] - glvp[0]).float, 1.0/(glvp[3] - glvp[1]).float, 1.0))

        let maskAlpha = msk.maskSprite.node.getGlobalAlpha()

        pushPostEffect(effect[msk.maskType.int-1], tex, maskImgCoords, maskBounds, trInv, maskAlpha)

method afterDraw*(msk: Mask, index: int) =
    if not msk.maskSprite.isNil and not msk.maskSprite.image.isNil and msk.maskType != tmNone:
        popPostEffect()

method serialize*(msk: Mask, serealizer: Serializer): JsonNode =
    result = newJObject()
    result.add("maskType", serealizer.getValue(msk.maskType))
    result.add("layerName", serealizer.getValue(msk.maskNode))

method deserialize*(msk: Mask, j: JsonNode, serealizer: Serializer) =
    serealizer.deserializeValue(j, "maskType", msk.maskType)
    var layerName: string
    serealizer.deserializeValue(j, "layerName", layerName)
    addNodeRef(msk.maskNode, layerName)

method visitProperties*(msk: Mask, p: var PropertyVisitor) =
    p.visitProperty("mask type", msk.maskType)
    p.visitProperty("layer name", msk.maskNode)

proc toPhantom(c: Mask, p: var object) =
    if not c.maskNode.isNil:
        p.layerName = c.maskNode.name

proc fromPhantom(c: Mask, p: object) =
    if p.layerName.len != 0:
        addNodeRef(c.maskNode, p.layerName)

genSerializationCodeForComponent(Mask)
registerComponent(Mask, "Effects")
