import json
import tables
import math
import typetraits

import nimx.types
import nimx.context
import nimx.image
import nimx.view
import nimx.matrixes
import nimx.composition
import nimx.property_visitor
import nimx.system_logger
import nimx.portable_gl
import nimx.class_registry

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

const comonPrefix = """
(sampler2D mask_img, vec4 mask_img_coords, vec4 mask_bounds, mat4 mvp_inv, float msk_alpha) {
    vec4 pos = mvp_inv * vec4(gl_FragCoord.xyz, 1.0);
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
(vec4 mask_bounds, vec4 mask_color, mat4 mvp_inv, float msk_alpha) {
    vec4 pos = mvp_inv * vec4(gl_FragCoord.xyz, 1.0);
    vec2 mskVpos = pos.xy / pos.w;
    vec2 b = mask_bounds.zw / 2.0;
    vec2 dp = mskVpos - (mask_bounds.xy + b);
    vec2 d = abs(dp) - b;
    float rect_alpha = min(min(max(d.x, d.y), 0.0) + length(max(d, 0.0)), 1.0);
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

template maskSolidPost(name, src: string): PostEffect =
    newPostEffect("void " & name & src, name, ["vec4", "vec4", "mat4", "float"])

var effectSolid = [
    maskSolidPost("maskSolidAlphaEffect", comonSolidPrefix & alphaPostfix), # tmAlpha
    maskSolidPost("maskSolidAlphaInvertedEffect", comonSolidPrefix & alphaInvertedPostfix), # tmAlphaInverted
    maskSolidPost("maskSolidLumaEffect", comonSolidPrefix & lumaPostfix), # tmLuma
    maskSolidPost("maskSolidLumaInvertedEffect", comonSolidPrefix & lumaInvertedPostfix) # tmLumaInverted
]

type MaskType* = enum
    tmNone, tmAlpha, tmAlphaInverted, tmLuma, tmLumaInverted

type MaskPushProc = proc(c: Component, maskType: MaskType): bool

type Mask* = ref object of Component
    maskType*: MaskType
    mMaskNode: Node
    pushPostProc: proc(m: MaskType): bool
    bWasPost: bool

Mask.properties:
    maskType
    layerName:
        phantom: string

template inv(m: Matrix4): Matrix4 =
    var res: Matrix4
    if not m.tryInverse(res):
        res.loadIdentity()
    res

proc getInvTransform(n: Node): Matrix4 =
    let vp = n.sceneView
    result = (vp.viewProjMatrix * n.worldTransform()).inv()
    result.scale(newVector3(2.0,2.0,2.0))
    result.translate(newVector3(-0.5, -0.5, -0.5))
    let glvp = currentContext().gl.getViewport()
    result.scale(newVector3(1.0/(glvp[2] - glvp[0]).float, 1.0/(glvp[3] - glvp[1]).float, 1.0))

var maskTypesRegistry = newTable[string, MaskPushProc]()

proc registerMaskType(T: typedesc[Component], pushPostProc: MaskPushProc) =
    maskTypesRegistry[typetraits.name(T)] = pushPostProc

proc getPostProc(c: Component): MaskPushProc =
    maskTypesRegistry[c.className()]

proc spriteMaskImpl(c: Component, maskType: MaskType): bool =
    let s = c.Sprite
    if not s.image.isNil:
        var theQuad {.noinit.}: array[4, GLfloat]
        let tex = getTextureQuad(s.image, currentContext().gl, theQuad)
        let maskImgCoords = newRect(theQuad[0], theQuad[1], theQuad[2], theQuad[3])
        let maskBounds = newRect(s.getOffset(), s.image.size)
        let trInv = s.node.getInvTransform()
        let maskAlpha = s.node.getGlobalAlpha()
        pushPostEffect(effect[maskType.int-1], tex, maskImgCoords, maskBounds, trInv, maskAlpha)
        return true

registerMaskType(Sprite, spriteMaskImpl)

proc solidMaskImpl(c: Component, maskType: MaskType): bool =
    let s = c.Solid
    let maskBounds = newRect(newPoint(0, 0), s.size)
    let trInv = s.node.getInvTransform()
    let maskAlpha = s.node.getGlobalAlpha()
    pushPostEffect(effectSolid[maskType.int-1], maskBounds, s.color, trInv, maskAlpha)
    return true

registerMaskType(Solid, solidMaskImpl)

registerMaskType(RTI, proc(c: Component, maskType: MaskType): bool =
    echo "------------im RTI "
)

proc findComponents*(n: Node, T: typedesc[Component]): auto =
    type TT = T
    var compSeq = newSeq[TT]()

    discard n.findNode do(nd: Node) -> bool:
        let comp = nd.componentIfAvailable(TT)
        if not comp.isNil: compSeq.add(comp)
    return compSeq

proc findRegisteredComponents*(n: Node): Table[string, seq[Component]] =
    var res = initTable[string, seq[Component]]()
    for k, v in maskTypesRegistry:
        res[k] = newSeq[Component]()
    discard n.findNode do(nd: Node) -> bool:
        for k, v in maskTypesRegistry:
            let comp = nd.componentIfAvailable(k)
            if not comp.isNil:
                res[k].add(comp)
        discard
    return res

proc setupMaskComponent(msk: Mask)
proc trySetupMask(msk: Mask)

proc `maskSprite=`*(msk: Mask, s: Sprite) {.deprecated.} =
    if s.isNil:
        msk.pushPostProc = nil
    else:
        let sprt = s
        let p = getPostProc(sprt)
        msk.pushPostProc = proc(maskType: MaskType): bool =
            return p(sprt, maskType)

template maskNode*(msk: Mask): Node = msk.mMaskNode
template `maskNode=`*(msk: Mask, val: Node) =
    msk.mMaskNode = val
    trySetupMask(msk)

proc setupMaskComponent(msk: Mask) =
    if not msk.maskNode.isNil:
        msk.pushPostProc = nil
        let components = msk.maskNode.findRegisteredComponents()
        for k, v in components:
            if v.len > 1:
                msk.pushPostProc = nil
                raise newException(Exception, "more than one mask targets found, use rti")
            elif v.len == 1:
                if msk.pushPostProc.isNil:
                    let cmp = v[0]
                    let p = getPostProc(cmp)
                    msk.pushPostProc = proc(maskType: MaskType): bool =
                        return p(cmp, maskType)
                else:
                    msk.pushPostProc = nil
                    raise newException(Exception, "more than one mask targets found, use rti")

proc trySetupMask(msk: Mask) =
    try: msk.setupMaskComponent()
    except Exception:
        let ex = getCurrentException()
        logi ex.name, ": ", getCurrentExceptionMsg(), "\n", ex.getStackTrace()

method componentNodeWasAddedToSceneView*(msk: Mask) =
    if msk.pushPostProc.isNil:
        msk.trySetupMask()

method componentNodeWillBeRemovedFromSceneView*(msk: Mask) =
    msk.pushPostProc = nil

method beforeDraw*(msk: Mask, index: int): bool =
    if msk.maskType != tmNone and not msk.pushPostProc.isNil:
        msk.bWasPost = msk.pushPostProc(msk.maskType)
    else:
        msk.bWasPost = false

method afterDraw*(msk: Mask, index: int) =
    if msk.bWasPost:
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
