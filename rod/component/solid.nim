import nimx/[types, context, matrixes, property_visitor]
import rod / utils / [ property_desc, serialization_codegen ]
import rod/[rod_types, component, node]
import rod/tools/serializer
import json

type Solid* = ref object of RenderComponent
    size*: Size
    color*: Color

Solid.properties:
    size
    color

method init*(s: Solid) =
    s.color = whiteColor()
    s.size = newSize(10, 10)

method deserialize*(s: Solid, j: JsonNode, serializer: Serializer) =
    var v = j{"color"}
    if not v.isNil:
        s.color = newColor(v[0].getFloat(), v[1].getFloat(), v[2].getFloat())
    v = j{"alpha"} # Deprecated.
    if not v.isNil:
        s.node.alpha = v.getFloat(1.0)

    v = j{"size"}
    if not v.isNil:
        s.size = newSize(v[0].getFloat(), v[1].getFloat())

genSerializationCodeForComponent(Solid)

method draw*(s: Solid) =
    let c = currentContext()
    var r: Rect
    r.size = s.size
    c.fillColor = s.color
    c.strokeWidth = 0
    c.drawRect(r)

method getBBox*(s: Solid): BBox =
    result.minPoint = newVector3(0.0, 0.0, 0.0)
    result.maxPoint = newVector3(s.size.width, s.size.height, 0.0)

method visitProperties*(c: Solid, p: var PropertyVisitor) =
    p.visitProperty("size", c.size)
    p.visitProperty("color", c.color)

method serialize*(c: Solid, s: Serializer): JsonNode =
    result = newJObject()
    result.add("size", s.getValue(c.size))
    result.add("color", s.getValue(c.color))

registerComponent(Solid)
