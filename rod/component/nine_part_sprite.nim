import nimx / [ types, context, image, animation, property_visitor ]
import rod / [rod_types, node, component, tools/serializer]
import rod / utils / [ property_desc, serialization_codegen ]
import rod/component/sprite
import json

type NinePartSprite* = ref object of Sprite
  mSize: Size
  segments: Vector4

NinePartSprite.properties:
  mSize
  segments:
    serializationKey: "segments"

proc size*(s: NinePartSprite): Size =
  s.mSize

proc `size=`*(s: NinePartSprite, v: Size) =
  s.mSize = v

template marginLeft(s: NinePartSprite): float32 = s.segments.x
template marginRight(s: NinePartSprite): float32 = s.segments.y
template marginTop(s: NinePartSprite): float32 = s.segments.z
template marginBottom(s: NinePartSprite): float32 = s.segments.w

proc `image=`*(s: NinePartSprite, i: Image) =
  procCall s.Sprite.`image=`(i)
  s.segments.x = i.size.width * 0.4
  s.segments.y = i.size.width * 0.4

  s.size = i.size
  # s.segments.z = i.size.height * 0.5
  # s.segments.w = i.size.height * 0.5

proc calculatedSize(s: NinePartSprite): Size =
  ## If size is zeroSize - return image size.
  # if not s.isNinePart:
  #   if not s.image.isNil:
  #     result = s.image.size
  # else:
  result = s.size

method draw*(s: NinePartSprite) =
  let c = currentContext()
  let i = s.image
  if not i.isNil:
    var r: Rect
    r.origin = s.getOffset()
    r.size = s.calculatedSize()
    c.drawNinePartImage(i, r, s.marginLeft, s.marginTop, s.marginRight, s.marginBottom)

genSerializationCodeForComponent(NinePartSprite)
registerComponent(NinePartSprite)

when defined(rodedit):
  type NinePartSegmentsAUX* = ref object
    segments*: Vector4
    image*: Image
    size*: Size

  proc segmentsAUX(s: NinePartSprite): NinePartSegmentsAUX =
    result = NinePartSegmentsAUX(segments: s.segments, image: s.image, size: s.size)

  proc `segmentsAUX=`*(s: NinePartSprite, v: NinePartSegmentsAUX) =
    s.segments = v.segments
    # s.image = v.image
    s.size = v.size

method visitProperties*(s: NinePartSprite, p: var PropertyVisitor) =
  # procCall s.Sprite.visitProperties(p)
  p.visitProperty("size", s.size)
  p.visitProperty("image", s.image)

  when defined(rodedit):
    p.visitProperty("nine part", s.segmentsAUX)
