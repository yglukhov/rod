import nimx / [ types, context, image, animation, property_visitor ]
import rod / [rod_types, node, component, tools/serializer]
import rod / utils / [ property_desc, serialization_codegen ]
import rod/component/sprite
import json

type NinePartSprite* = ref object of Sprite
  mSize: Size
  segments: Vector4

NinePartSprite.properties:
  mSize:
    serializationKey: "size"
  segments

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
  s.segments.z = i.size.height * 0.4
  s.segments.w = i.size.height * 0.4

  s.size = i.size

method getBBox*(s: NinePartSprite): BBox =
    let sz = s.size
    result.maxPoint = newVector3(sz.width + s.getOffset.x, sz.height + s.getOffset.y, 0.0)
    result.minPoint = newVector3(s.getOffset.x, s.getOffset.y, 0.0)

method draw*(s: NinePartSprite) =
  let c = currentContext()
  let i = s.image
  if not i.isNil:
    var r: Rect
    r.origin = s.getOffset()
    r.size = s.size
    c.drawNinePartImage(i, r, s.marginLeft, s.marginTop, s.marginRight, s.marginBottom)

# hack serializer/deserializer from sprite
method serialize*(c: NinePartSprite, s: Serializer): JsonNode =
  result = procCall c.Sprite.serialize(s)
  var r2 = procCall c.Component.serialize(s)
  for k, v in r2:
    result[k] = v

method deserialize*(c: NinePartSprite, j: JsonNode, s: Serializer) =
  procCall c.Sprite.deserialize(j, s)
  procCall c.Component.deserialize(j, s)

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

method visitProperties*(s: NinePartSprite, p: var PropertyVisitor) =
  p.visitProperty("image", s.image)
  p.visitProperty("size", s.size)
  p.visitProperty("segments", s.segments)

  when defined(rodedit):
    p.visitProperty("nine part", s.segmentsAUX)
