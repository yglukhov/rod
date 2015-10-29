import json

import nimx.types
import nimx.context

import rod.component

type Solid* = ref object of Component
    size*: Size
    color*: Color

method init*(s: Solid) =
    s.color = whiteColor()

method deserialize*(s: Solid, j: JsonNode) =
    var v = j["alpha"]
    #if not v.isNil:
    #    s.color.a = v.getFNum(1.0)

    v = j["size"]
    if not v.isNil:
        s.size = newSize(v[0].getFNum(), v[1].getFNum())

method draw*(s: Solid) =
    let c = currentContext()
    var r: Rect
    r.size = s.size
    c.fillColor = s.color
    c.strokeWidth = 0
    c.drawRect(r)

method animatableProperty1*(s: Solid, name: string): proc (v: Coord) =
    case name
    of "alpha": result = proc (v: Coord) =
        s.color.a = v
    else: result = nil

registerComponent[Solid]()
