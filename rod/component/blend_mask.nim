import nimx / [ types, context, image, view, matrixes, composition, property_visitor, portable_gl, render_to_image ]
import rod / utils / [ property_desc, serialization_codegen ]
import rod / [ rod_types, node, component, viewport ]
import rod / component / [ sprite, solid, rti ]
import json, tables, logging

type BlendMaskType* = enum
  tmNone, tmAlpha, tmAlphaInverted, tmLuma, tmLumaInverted

type BlendTest = enum
  zero
  one

  src_color
  one_minus_src_color

  src_alpha
  one_minus_src_alpha

  dst_alpha
  one_minus_dst_alpha

  dst_color
  one_minus_dst_color

  src_alpha_saturate

  constant_color
  one_minus_constant_color

  constant_alpha
  one_minus_constant_alpha


proc toBlend(b: BlendTest): GLenum =
  const rr = [0, 1, 0x0300, 0x0301, 0x0302, 0x0303, 0x0304, 0x0305, 0x0306, 0x0307, 0x0308, 0x8001, 0x8002, 0x8003, 0x8004]
  result = rr[b.int].GLEnum

type BlendMask* = ref object of RTI
  mMaskNode: Node
  maskType*: BlendMaskType
  mWasPost: bool
  b1,b2,b3,b4: BlendTest
  invers: bool
  overrideBlends: bool

BlendMask.properties:
  maskType
  layerName:
    phantom: string

method init(c: BlendMask) =
  procCall c.RTI.init()
  c.drawInImage = true

proc maskNode*(c: BlendMask): Node =
  c.mMaskNode

proc `maskNode=`*(c: BlendMask, val: Node) =
  c.mMaskNode = val

method beforeDraw*(c: BlendMask, index: int): bool =
  result = procCall c.RTI.beforeDraw(index)
  if c.mMaskNode.isNil or c.maskType == tmNone: return

proc pushBlending(c: BlendMask) =
  let gl = currentContext().gl
  if not c.overrideBlends:
    case c.maskType:
    of tmAlphaInverted:
      c.b1 = zero
      c.b2 = one_minus_src_alpha
      c.b3 = zero
      c.b4 = one_minus_src_alpha
    of tmAlpha:
      c.b1 = one
      c.b2 = one_minus_dst_alpha
      c.b3 = dst_alpha
      c.b4 = zero
    else:
      discard
  gl.blendFuncSeparate(c.b1.toBlend, c.b2.toBlend, c.b3.toBlend, c.b4.toBlend)

proc popBlending(c: BlendMask) =
  let gl = currentContext().gl
  gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)

proc drawMaskNode(c: BlendMask) =
  if c.mMaskNode.isNil: return
  let tr = c.node.sceneView.viewProjMatrix * c.mMaskNode.worldTransform
  let ctx = currentContext()
  ctx.withTransform tr:
    let e = c.mMaskNode.enabled
    c.mMaskNode.enabled = true
    c.mMaskNode.recursiveDraw()
    c.mMaskNode.enabled = e

method beforeChild*(c: BlendMask) =
  if not c.invers:
    # c.bBlendOne = false
    c.drawMaskNode()
    c.pushBlending()

method prePostImage*(c: BlendMask) =
  if c.invers:
    # c.bBlendOne = true
    c.pushBlending()
    c.drawMaskNode()
  c.popBlending()

method visitProperties*(c: BlendMask, p: var PropertyVisitor) =
  p.visitProperty("mask type", c.maskType)
  p.visitProperty("layer name", c.maskNode)

  p.visitProperty("invers", c.invers)
  p.visitProperty("overrideBlends", c.overrideBlends)
  if c.overrideBlends:
    p.visitProperty("srcCol", c.b1)
    p.visitProperty("dstCol", c.b2)
    p.visitProperty("srcAlpha", c.b3)
    p.visitProperty("dstAlpha", c.b4)

  procCall c.RTI.visitProperties(p)

proc toPhantom(msk: BlendMask, p: var object) =
  if not msk.maskNode.isNil:
    p.layerName = msk.maskNode.name

proc fromPhantom(msk: BlendMask, p: object) =
  if p.layerName.len != 0:
    addNodeRef(p.layerName) do(n: Node):
      msk.maskNode = n

# method componentNodeWasAddedToSceneView(c: Mask) =
#   if c.renderTarget.isNil:
#     c.renderTarget = newImageRenderTarget()
#     # c.auxChild = c.node.newChild()
#     # for rc in c.node.renderComponents:
#     #   if rc != c:

#     #     c.auxChild.setComponent()


# method componentNodeWillBeRemovedFromSceneView*(c: Mask) =
#   if not c.renderTarget.isNil:
#     c.renderTarget.dispose()

genSerializationCodeForComponent(BlendMask)
registerComponent(BlendMask, "Effects")
