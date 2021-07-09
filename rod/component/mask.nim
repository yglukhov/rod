import nimx/[types, context, image, view, matrixes, composition, property_visitor, portable_gl, render_to_image]
import rod / utils / [ property_desc, serialization_codegen ]
import rod / [ rod_types, node, component, viewport, component/camera ]
import rod / component / [ sprite, solid, rti ]
import json, tables, logging, strutils
import times

template logp(t: untyped, args: varargs[string, `$`]) =
    block:
        var `lastPrint t` {.global.} = epochTime()
        if epochTime() - `lastPrint t` > 1.0:
            `lastPrint t` = epochTime()
            info args.join(" ")


const comonSpritePrefix = """
(sampler2D mask_img, vec4 mask_img_coords, vec4 mask_bounds, vec2 vp_size, mat4 mvp_inv, float msk_alpha) {
    vec2 uv = gl_FragCoord.xy / mask_bounds;
    vec4 mask_color = texture2D(mask_img, uv);
    float rect_alpha = 1.0;
"""

const comonSolidPrefix = """
(vec2 mask_size, vec4 mask_color, vec2 vp_size, mat4 mvp_inv, float msk_alpha) {
    vec2 xy = gl_FragCoord.xy / vp_size;
    vec4 pos = mvp_inv * vec4(xy, 1.0, 1.0);
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

type Mask* = ref object of RenderComponent
    when defined(rodplugin):
        mMaskNode: Node
    maskComponent*: Component
    maskType*: MaskType
    mWasPost: bool
    rti: ImageRenderTarget
    maskTexture: SelfContainedImage
    dx,dy: float
    dw,dh: float

Mask.properties:
    maskType
    layerName:
        phantom: string

proc getInvTransform(n: Node): Matrix4 =
    let vp = n.sceneView
    if not vp.isNil:
        result = vp.viewProjMatrix * n.worldTransform()

proc getVpSize(): Size =
    let glvp = currentContext().gl.getViewport()
    result = newSize((glvp[2] - glvp[0]).float32, (glvp[3] - glvp[1]).float32)
    # info "VP ", result

proc getVpSize(c: Component): Size =
  c.node.sceneView.bounds.size

method isMaskAplicable2(c: Component): bool {.base.} = false
method isMaskAplicable2(s: Sprite): bool = true
method isMaskAplicable2(s: Solid): bool = true

proc setupMskPost(c: Mask): bool =
    if c.rti.isNil:
        c.rti = newImageRenderTarget()

    let mskN = c.maskComponent.node
    let bbx = mskN.nodeBounds()
    let scm = c.node.sceneView.worldToScreenPoint(bbx.minPoint)
    var wpmin = c.node.sceneView.convertPointToWindow(newPoint(scm.x, scm.y))
    let scmax = c.node.sceneView.worldToScreenPoint(bbx.maxPoint)
    var wpmax = c.node.sceneView.convertPointToWindow(newPoint(scmax.x, scmax.y))
    let s = newSize(wpmax.x - wpmin.x, wpmax.y - wpmin.y)
    if s.width < 1.0 or s.height < 1.0: return false
    let gl = currentContext().gl

    # logp(size, s)
    if c.maskTexture.isNil:
        c.maskTexture = imageWithSize(s)
    elif c.maskTexture.size != s:
        c.maskTexture.resetToSize(s, gl)

    let oldVp = gl.getViewport()
    let ws = getVpSize()
    var ctx: RTIContext
    c.rti.setImage(c.maskTexture)
    c.rti.beginDraw(ctx)

    # proc viewport*(gl: GL, x, y: GLint, width, height: GLsizei)
    # logp(viewport, scm.x.GLint, scm.y.GLint, (scmax.x - scm.x).GLSizei, (scmax.y - scm.y).GLSizei)
    # logp(ss, wpmin, wpmax)
    # let rw = ws.width / s.with
    # let rh = ws.height / s.height
    let wr = ws.width / ws.height
    let mr = s.width / s.height
    let rrw = ws.width / s.width
    let rrh = ws.height / s.height
    # if c.dw < 1.0:
    c.dx = -wpmin.x
    c.dw = s.width * (rrw / mr)
    c.dh = s.height * (rrh / mr)
    size.logp(c.dw, c.dh, wr, mr, rrw, rrh, wpmin)
    gl.viewport(c.dx.GLint, c.dy.GLint, c.dw.GLSizei, c.dh.GLSizei)

    let e = mskN.enabled
    mskN.enabled = true
    recursiveDraw(mskN)
    mskN.enabled = e
    c.rti.endDraw(ctx)
    gl.viewport(oldVp)


    if not c.maskTexture.flipped:
        c.maskTexture.flipVertically()

    var theQuad {.noinit.}: array[4, GLfloat]
    let tex = getTextureQuad(c.maskTexture, currentContext().gl, theQuad)
    let maskImgCoords = newRect(theQuad[0], theQuad[1], theQuad[2], theQuad[3])
    let maskBounds = newRect(zeroPoint, c.maskTexture.size)
    let trInv = mskN.getInvTransform()
    let maskAlpha = mskN.getGlobalAlpha()
    pushPostEffect(effectSprite[c.maskType.int-1], tex, maskImgCoords, maskBounds, getVpSize(), trInv, maskAlpha)
    result = true

proc setupMaskComponent(msk: Mask, n: Node) =
    msk.maskComponent = nil
    if not n.isNil:
        discard n.findNode do(nd: Node) -> bool:
            for comp in nd.components:
                if comp.isMaskAplicable2():
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

# method componentNodeWillBeRemovedFromSceneView*(msk: Mask) =
#     msk.maskComponent = nil

method beforeDraw*(msk: Mask, index: int): bool =
    if not msk.maskComponent.isNil and msk.maskType != tmNone:
        # msk.mWasPost = msk.maskComponent.setupMaskPost2(msk.maskType)
        msk.mWasPost = msk.setupMskPost()

method afterDraw*(msk: Mask, index: int) =
    if msk.mWasPost:
        popPostEffect()
        msk.mWasPost = false

method visitProperties*(msk: Mask, p: var PropertyVisitor) =
    p.visitProperty("mask type", msk.maskType)
    p.visitProperty("layer name", msk.maskNode)

    p.visitProperty("dx", msk.dx)
    p.visitProperty("dy", msk.dy)
    p.visitProperty("dw", msk.dw)
    p.visitProperty("dh", msk.dh)


    proc prev(c: Mask): Image =
        if not c.maskTexture.isNil:
            return c.maskTexture.Image
    proc `prev=`(c: Mask, v: Image) = discard
    p.visitProperty("mask texture", msk.prev)

proc toPhantom(msk: Mask, p: var object) =
    if not msk.maskNode.isNil:
        p.layerName = msk.maskNode.name

proc fromPhantom(msk: Mask, p: object) =
    if p.layerName.len != 0:
        addNodeRef(p.layerName) do(n: Node):
            msk.maskNode = n

genSerializationCodeForComponent(Mask)
registerComponent(Mask, "Effects")
