import json, tables, math, logging

import nimx.types
import nimx.context
import nimx.image
import nimx.view
import nimx.matrixes
import nimx.composition
import nimx.property_visitor
import nimx.portable_gl

import rod.rod_types
import rod.node
import rod.tools.serializer
import rod / utils / [ property_desc, serialization_codegen ]
import rod.component
import rod.component.sprite
import rod.component.solid
import rod.component.rti
import rod.component.camera
import rod.viewport

const comonSpritePrefix = """
(sampler2D mask_img, vec4 mask_img_coords, vec4 mask_bounds, vec2 vp_size, mat4 mvp_inv, float msk_alpha) {
    vec2 xy = gl_FragCoord.xy / vp_size;
    vec4 pos = mvp_inv * vec4(xy, gl_FragCoord.z, 1.0);
    vec2 mskVpos = pos.xy / pos.w;
    vec2 destuv = ( mskVpos - mask_bounds.xy ) / mask_bounds.zw;
    vec2 uv = mask_img_coords.xy + (mask_img_coords.zw - mask_img_coords.xy) * destuv;
    vec4 mask_color = texture2D(mask_img, uv);
    float rect_alpha = 1.0;
    if (uv.x < mask_img_coords.x || uv.x > mask_img_coords.z || uv.y < mask_img_coords.y || uv.y > mask_img_coords.w) {
        rect_alpha = 0.0;
    }
"""

const comonSolidPrefix = """
(vec2 mask_size, vec4 mask_color, vec2 vp_size, mat4 mvp_inv, float msk_alpha) {
    vec2 xy = gl_FragCoord.xy / vp_size;
    vec4 pos = mvp_inv * vec4(xy, gl_FragCoord.z, 1.0);
    vec2 mskVpos = pos.xy / pos.w;
    vec2 b = mask_size.xy / 2.0;
    vec2 dp = mskVpos - b;
    vec2 d = abs(dp) - b;
    float rect_alpha = 1.0 - min(min(max(d.x, d.y), 0.0) + length(max(d, 0.0)), 1.0);
    rect_alpha = step(0.0000001, rect_alpha);
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
    newPostEffect("void " & name & src, name, ["sampler2D", "vec4", "vec4", "vec2", "mat4", "float"])

var effectSprite = [
    maskPost("maskAlphaEffect", comonSpritePrefix & alphaPostfix), # tmAlpha
    maskPost("maskAlphaInvertedEffect", comonSpritePrefix & alphaInvertedPostfix), # tmAlphaInverted
    maskPost("maskLumaEffect", comonSpritePrefix & lumaPostfix), # tmLuma
    maskPost("maskLumaInvertedEffect", comonSpritePrefix & lumaInvertedPostfix) # tmLumaInverted
]

template maskSolidPost(name, src: string): PostEffect =
    newPostEffect("void " & name & src, name, ["vec2", "vec4", "vec2", "mat4", "float"])

var effectSolid = [
    maskSolidPost("maskSolidAlphaEffect", comonSolidPrefix & alphaPostfix), # tmAlpha
    maskSolidPost("maskSolidAlphaInvertedEffect", comonSolidPrefix & alphaInvertedPostfix), # tmAlphaInverted
    maskSolidPost("maskSolidLumaEffect", comonSolidPrefix & lumaPostfix), # tmLuma
    maskSolidPost("maskSolidLumaInvertedEffect", comonSolidPrefix & lumaInvertedPostfix) # tmLumaInverted
]

type MaskType* = enum
    tmNone, tmAlpha, tmAlphaInverted, tmLuma, tmLumaInverted

type Mask* = ref object of Component
    when defined(rodplugin):
        mMaskNode: Node
    maskComponent*: Component
    maskType*: MaskType
    mWasPost: bool

Mask.properties:
    maskType
    layerName:
        phantom: string

proc getInvTransform(n: Node): Matrix4 =
    let vp = n.sceneView
    if not vp.isNil:
        result = vp.viewProjMatrix * n.worldTransform()
        if not result.tryInverse(result):
            result.loadIdentity()
        result.scale(newVector3(2.0,2.0,2.0))
        result.translate(newVector3(-0.5, -0.5, -0.5))

proc getVpSize(): Size =
    let glvp = currentContext().gl.getViewport()
    result = newSize((glvp[2] - glvp[0]).float32, (glvp[3] - glvp[1]).float32)

method isMaskAplicable(c: Component): bool {.base.} = false
method setupMaskPost(c: Component, maskType: MaskType): bool {.base.} = false

method isMaskAplicable(s: Sprite): bool = true
method setupMaskPost(s: Sprite, maskType: MaskType): bool =
    if not s.image.isNil:
        var theQuad {.noinit.}: array[4, GLfloat]
        let tex = getTextureQuad(s.image, currentContext().gl, theQuad)
        let maskImgCoords = newRect(theQuad[0], theQuad[1], theQuad[2], theQuad[3])
        let maskBounds = newRect(s.getOffset(), s.image.size)
        let trInv = s.node.getInvTransform()
        let maskAlpha = s.node.getGlobalAlpha()
        pushPostEffect(effectSprite[maskType.int-1], tex, maskImgCoords, maskBounds, getVpSize(), trInv, maskAlpha)
        return true

method isMaskAplicable(s: Solid): bool = true
method setupMaskPost(s: Solid, maskType: MaskType): bool =
    pushPostEffect(effectSolid[maskType.int-1], s.size, s.color, getVpSize(), s.node.getInvTransform(), s.node.getGlobalAlpha())
    return true

proc setupMaskComponent(msk: Mask, n: Node) =
    msk.maskComponent = nil
    if not n.isNil:
        discard n.findNode do(nd: Node) -> bool:
            for comp in nd.components:
                if comp.isMaskAplicable():
                    if msk.maskComponent.isNil:
                        msk.maskComponent = comp
                        if comp of RTI:
                            return true
                    else:
                        raise newException(Exception, "more than one mask targets found, use rti")

proc trySetupMask(msk: Mask, n: Node) =
    try: msk.setupMaskComponent(n)
    except Exception:
        let ex = getCurrentException()
        info ex.name, ": ", getCurrentExceptionMsg(), "\n", ex.getStackTrace()

template maskNode*(msk: Mask): Node =
    when defined(rodplugin):
        msk.mMaskNode
    else:
        if not msk.maskComponent.isNil: msk.maskComponent.node else: nil

template `maskNode=`*(msk: Mask, val: Node) =
    when defined(rodplugin):
        msk.mMaskNode = val
    trySetupMask(msk, val)

#method componentNodeWillBeRemovedFromSceneView*(msk: Mask) =
#    msk.maskComponent = nil

method beforeDraw*(msk: Mask, index: int): bool =
    if not msk.maskComponent.isNil and msk.maskType != tmNone:
        msk.mWasPost = msk.maskComponent.setupMaskPost(msk.maskType)

method afterDraw*(msk: Mask, index: int) =
    if msk.mWasPost:
        popPostEffect()
        msk.mWasPost = false

method visitProperties*(msk: Mask, p: var PropertyVisitor) =
    p.visitProperty("mask type", msk.maskType)
    p.visitProperty("layer name", msk.maskNode)

proc toPhantom(msk: Mask, p: var object) =
    if not msk.maskNode.isNil:
        p.layerName = msk.maskNode.name

proc fromPhantom(msk: Mask, p: object) =
    if p.layerName.len != 0:
        addNodeRef(p.layerName) do(n: Node):
            msk.maskNode = n

method serialize*(msk: Mask, serealizer: Serializer): JsonNode =
    result = newJObject()
    result.add("maskType", serealizer.getValue(msk.maskType))
    result.add("layerName", serealizer.getValue(msk.maskNode))

method deserialize*(msk: Mask, j: JsonNode, serealizer: Serializer) =
    serealizer.deserializeValue(j, "maskType", msk.maskType)
    var layerName: string
    serealizer.deserializeValue(j, "layerName", layerName)
    addNodeRef(layerName) do(n: Node):
        msk.maskNode=n

genSerializationCodeForComponent(Mask)
registerComponent(Mask, "Effects")
