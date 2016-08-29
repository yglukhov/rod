import json

import nimx.types
import nimx.context
import nimx.matrixes
import nimx.property_visitor

import rod.node
import rod.component
import rod.tools.serializer

type Solid* = ref object of Component
    size*: Size
    color*: Color

method init*(s: Solid) =
    s.color = whiteColor()
    s.size = newSize(10, 10)

method deserialize*(s: Solid, j: JsonNode, serializer: Serializer) =
    var v = j{"color"}
    if not v.isNil:
        s.color = newColor(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    v = j{"alpha"} # Deprecated.
    if not v.isNil:
        s.node.alpha = v.getFNum(1.0)

    v = j{"size"}
    if not v.isNil:
        s.size = newSize(v[0].getFNum(), v[1].getFNum())

method draw*(s: Solid) =
    let c = currentContext()
    var r: Rect
    r.size = s.size
    c.fillColor = s.color
    c.strokeWidth = 0
    c.drawRect(r)

method visitProperties*(c: Solid, p: var PropertyVisitor) =
    p.visitProperty("size", c.size)
    p.visitProperty("color", c.color)

method serialize*(c: Solid, s: Serializer): JsonNode =
    result = newJObject()
    result.add("size", s.getValue(c.size))
    result.add("color", s.getValue(c.color))

registerComponent(Solid)
