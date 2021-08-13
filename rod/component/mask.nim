import nimx / [
  types, context, image, view, matrixes, composition,
  property_visitor, portable_gl, render_to_image, window
]
import rod / utils / [ property_desc, serialization_codegen ]
import rod / [ rod_types, node, component, viewport, component/camera ]

const comonSpritePrefix = """
(sampler2D maskTexture, vec4 texCoords, vec4 mask_bounds, vec2 vp_size, float msk_alpha) {
  float x = (gl_FragCoord.x - mask_bounds.x) / mask_bounds.z;
  float y = (vp_size.y - gl_FragCoord.y - mask_bounds.y) / mask_bounds.w;
  vec2 uv = texCoords.xy + (texCoords.zw - texCoords.xy) * vec2(x, y);
  vec4 mask_color = texture2D(maskTexture, uv);
  mask_color.a *= msk_alpha;

  // clamp texture, or migrate to ES3.2 and use GL_CLAMP_TO_BORDER
  float tcW = max(texCoords.x, texCoords.z);
  float tcH = max(texCoords.y, texCoords.w);
  vec4 clearColor = vec4(0.0);
  mask_color = mix(clearColor, mask_color, step(0.0001, uv.x));
  mask_color = mix(clearColor, mask_color, step(0.0001, uv.y));
  mask_color = mix(mask_color, clearColor, step(tcW, uv.x));
  mask_color = mix(mask_color, clearColor, step(tcH, uv.y));
"""

const alphaPostfix = """
  float mask_alpha = mask_color.a;
  gl_FragColor.a *= mask_alpha;
}
"""
const alphaInvertedPostfix = """
  float mask_alpha = mask_color.a;
  mask_alpha = 1.0 - clamp(mask_alpha, 0.0, 1.0);
  gl_FragColor.a *= mask_alpha;
}
"""
const lumaPostfix = """
  float luma = dot(mask_color.rgb, vec3(0.299, 0.587, 0.114));
  float mask_alpha = luma * mask_color.a;
  gl_FragColor.a *= mask_alpha;
}
"""
const lumaInvertedPostfix = """
  float luma = dot(mask_color.rgb, vec3(0.299, 0.587, 0.114));
  float mask_alpha = luma * mask_color.a;
  mask_alpha = 1.0 - clamp(mask_alpha, 0.0, 1.0);
  gl_FragColor.a *= mask_alpha;
}
"""

template maskPost(name, src: string): PostEffect =
  newPostEffect("void " & name & src, name, ["sampler2D", "vec4", "vec4", "vec2", "float"])

var effectSprite = [
  maskPost("maskAlphaEffect", comonSpritePrefix & alphaPostfix), # tmAlpha
  maskPost("maskAlphaInvertedEffect", comonSpritePrefix & alphaInvertedPostfix), # tmAlphaInverted
  maskPost("maskLumaEffect", comonSpritePrefix & lumaPostfix), # tmLuma
  maskPost("maskLumaInvertedEffect", comonSpritePrefix & lumaInvertedPostfix) # tmLumaInverted
]

type MaskType* = enum
  tmNone, tmAlpha, tmAlphaInverted, tmLuma, tmLumaInverted

type Mask* = ref object of RenderComponent
  mMaskNode: Node
  maskType*: MaskType
  mWasPost: bool
  rti: ImageRenderTarget
  maskTexture: SelfContainedImage

Mask.properties:
  maskType
  layerName:
    phantom: string


template worldToWindow(c: Mask, w: Vector3): Point =
  let s = c.node.sceneView
  let scr = s.worldToScreenPoint(w)
  s.convertPointToWindow(newPoint(scr.x, scr.y)) * s.window.viewportPixelRatio

proc drawMaskNode(c: Mask, mskN: Node) =
  let e = mskN.enabled
  mskN.enabled = true
  let gl = currentContext().gl
  let sc = gl.getParamb(gl.SCISSOR_TEST)
  if sc:
    gl.disable(gl.SCISSOR_TEST)
  recursiveDraw(mskN)
  if sc:
    gl.enable(gl.SCISSOR_TEST)
  mskN.enabled = e

var theQuad {.noinit.}: array[4, GLfloat]
proc setupMskPost(c: Mask): bool =
  if c.rti.isNil:
    c.rti = newImageRenderTarget()

  let gl = currentContext().gl
  let bbx = c.mMaskNode.nodeBounds()
  var wpmin = c.worldToWindow(bbx.minPoint)
  var wpmax = c.worldToWindow(bbx.maxPoint)

  let isOrtho = c.node.sceneView.camera.projectionMode == cpOrtho
  if not isOrtho:
    swap(wpmin.y, wpmax.y)

  let
    oldVp = gl.getViewport()
    vpW = (oldVp[2] - oldVp[0]).float32
    vpH = (oldVp[3] - oldVp[1]).float32
    vpX = -wpmin.x
    vpY = -(vpH - wpmax.y)

  let s = newSize(
    min(wpmax.x - wpmin.x, vpW),
    min(wpmax.y - wpmin.y, vpH)
  )

  if s.width < 1.0 or s.height < 1.0:
    return false

  if c.maskTexture.isNil:
    c.maskTexture = imageWithSize(s)
  elif (c.maskTexture.size - s).width.abs > 0.01 or (c.maskTexture.size - s).height.abs > 0.01:
    c.maskTexture.resetToSize(s, gl)

  var ctx: RTIContext
  c.rti.setImage(c.maskTexture)
  c.rti.beginDraw(ctx)
  gl.viewport(vpX.GLint, vpY.GLint, vpW.GLsizei, vpH.GLsizei)
  c.drawMaskNode(c.mMaskNode)
  c.rti.endDraw(ctx)
  gl.viewport(oldVp)

  if not c.maskTexture.flipped:
    c.maskTexture.flipVertically()

  let tex = getTextureQuad(c.maskTexture, currentContext().gl, theQuad)
  let texCoords = newRect(theQuad[0], theQuad[1], theQuad[2], theQuad[3])
  pushPostEffect(effectSprite[c.maskType.int-1], tex, texCoords, newRect(wpmin, s), newSize(vpW, vpH), c.mMaskNode.getGlobalAlpha())
  result = true

template maskNode*(msk: Mask): Node =
  msk.mMaskNode

template `maskNode=`*(msk: Mask, val: Node) =
  msk.mMaskNode = val

method componentNodeWillBeRemovedFromSceneView*(c: Mask) =
  if not c.rti.isNil:
    c.rti.dispose()
    c.rti = nil
  c.maskTexture = nil

method beforeDraw*(msk: Mask, index: int): bool =
  if not msk.mMaskNode.isNil and msk.maskType != tmNone:
    msk.mWasPost = msk.setupMskPost()

method afterDraw*(msk: Mask, index: int) =
  if msk.mWasPost:
    popPostEffect()
    msk.mWasPost = false

method visitProperties*(msk: Mask, p: var PropertyVisitor) =
  p.visitProperty("mask type", msk.maskType)
  p.visitProperty("layer name", msk.maskNode)

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
