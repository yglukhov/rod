import json
import tables
import math

import nimx.types
import nimx.context
import nimx.image
import nimx.view
import nimx.composition
import nimx.property_visitor
import nimx.system_logger
import nimx.render_to_image

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod.component
import rod.component.sprite
import rod.component.solid
import rod.component.camera
import rod.viewport

const rectAlpha* = """
float rect_alpha(vec2 uvs, vec4 texCoord) {
    if (uvs.x < texCoord.x || uvs.x > texCoord.z || uvs.y < texCoord.y || uvs.y > texCoord.w) { return 0.0; }
    else { return 1.0; }
}
"""
const getMaskUV* = """
vec2 get_mask_uv(vec4 mask_img_coords, vec4 mask_bounds, mat4 mvp_inv) {
    vec2 mskVpos = vec4(mvp_inv * vec4(vPos.xy, 0.0, 1.0)).xy;
    vec2 destuv = ( mskVpos - mask_bounds.xy ) / mask_bounds.zw;
    return mask_img_coords.xy + (mask_img_coords.zw - mask_img_coords.xy) * destuv;
}
"""
const getRGBLuma* = """
float rgb_luma(vec3 col) {
    return dot(col, vec3(0.299, 0.587, 0.114));
}
"""
const maskEffectPrefix = """
void mask_effect(sampler2D mask_img, vec4 mask_img_coords, vec4 mask_bounds, mat4 mvp_inv, float msk_alpha) {
    vec2 uv = get_mask_uv(mask_img_coords, mask_bounds, mvp_inv);
    vec4 mask_color = texture2D(mask_img, uv);
"""
const maskEffectPostfixAlpha = """
    float mask_alpha = mask_color.a * rect_alpha(uv, mask_img_coords) * msk_alpha;
    gl_FragColor.a *= mask_alpha;
}
"""
const maskEffectPostfixAlphaInv = """
    float mask_alpha = mask_color.a * rect_alpha(uv, mask_img_coords) * msk_alpha;
    gl_FragColor.a *= 1.0 - mask_alpha;
}
"""
const maskEffectPostfixLuma = """
    float luma = rgb_luma(mask_color.rgb);
    float mask_alpha = luma * mask_color.a * rect_alpha(uv, mask_img_coords) * msk_alpha;
    gl_FragColor.a *= mask_alpha;
}
"""
const maskEffectPostfixLumaInv = """
    float luma = rgb_luma(mask_color.rgb);
    float mask_alpha = luma * mask_color.a * rect_alpha(uv, mask_img_coords) * msk_alpha;
    gl_FragColor.a *= 1.0 - mask_alpha;
}
"""

template maskPost(src: string): PostEffect =
    newPostEffect(src, "mask_effect", ["sampler2D", "vec4", "vec4", "mat4", "float"])

var effect = [
    maskPost(rectAlpha & getMaskUV & maskEffectPrefix & maskEffectPostfixAlpha), # tmAlpha
    maskPost(rectAlpha & getMaskUV & maskEffectPrefix & maskEffectPostfixAlphaInv), # tmAlphaInverted
    maskPost(rectAlpha & getMaskUV & getRGBLuma & maskEffectPrefix & maskEffectPostfixLuma), # tmLuma
    maskPost(rectAlpha & getMaskUV & getRGBLuma & maskEffectPrefix & maskEffectPostfixLumaInv) # tmLumaInverted
]

type MaskType* = enum
    tmNone, tmAlpha, tmAlphaInverted, tmLuma, tmLumaInverted

type Mask* = ref object of Component
    mMaskType: MaskType
    mMaskNode: Node
    mMaskSprite: Sprite
    mWithRTI: bool

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

template maskSprite*(msk: Mask): Sprite = msk.mMaskSprite
template `maskSprite=`*(msk: Mask, val: Sprite) = msk.mMaskSprite = val

template maskType*(msk: Mask): MaskType = msk.mMaskType
template `maskType=`*(msk: Mask, val: MaskType) = msk.mMaskType = val

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

method beforeDraw*(msk: Mask, index: int): bool =
    if not msk.maskSprite.isNil and msk.maskType != tmNone:

        if msk.mWithRTI:
            # TODO RTI
            discard

        var theQuad {.noinit.}: array[4, GLfloat]
        discard getTextureQuad(msk.maskSprite.image, currentContext().gl, theQuad)
        let maskImgCoords = newRect(theQuad[0], theQuad[1], theQuad[2], theQuad[3])
        let maskBounds = newRect(msk.maskSprite.getOffset(), msk.maskSprite.image.size)
        let trInv = (msk.node.worldTransform.inv() * msk.maskSprite.node.worldTransform()).inv()
        let maskAlpha = msk.maskSprite.node.getGlobalAlpha()

        pushPostEffect(effect[msk.maskType.int-1], msk.maskSprite.image, maskImgCoords, maskBounds, trInv, maskAlpha)

method afterDraw*(msk: Mask, index: int) =
    if not msk.maskSprite.isNil and msk.maskType != tmNone:
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

registerComponent(Mask, "Effects")
