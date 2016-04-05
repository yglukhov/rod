import json

import nimx.types
import nimx.context
import nimx.matrixes

import rod.component
import rod.property_visitor

type Solid* = ref object of Component
    size*: Size
    color*: Color

method init*(s: Solid) =
    s.color = whiteColor()

method deserialize*(s: Solid, j: JsonNode) =
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

registerComponent[Solid]()
