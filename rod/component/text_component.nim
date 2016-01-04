import json
import nimx.types
import nimx.font
import nimx.context

import rod.component
import rod.property_visitor

type TextJustification* = enum
    tjLeft
    tjCenter
    tjRight

type Text* = ref object of Component
    text*: string
    color*: Color
    font*: Font
    trackingAmount*: Coord
    justification*: TextJustification

method init*(t: Text) =
    t.color = blackColor()
    t.font = systemFont()

method deserialize*(t: Text, j: JsonNode) =
    var v = j["text"]
    if not v.isNil:
        t.text = v.getStr()

    v = j["color"]
    if not v.isNil:
        t.color = newColor(v[0].getFnum(), v[1].getFnum(), v[2].getFnum())
        if v.len > 3: # Deprecated
            t.node.alpha = v[3].getFnum()

    v = j["fontSize"]
    if not v.isNil:
        t.font = systemFontOfSize(v.getFNum())

    v = j["justification"]
    if not v.isNil:
        case v.getStr()
        of "left": t.justification = tjLeft
        of "center": t.justification = tjCenter
        of "right": t.justification = tjRight
        else: discard

method draw*(t: Text) =
    if not t.text.isNil:
        let c = currentContext()
        c.fillColor = t.color
        var p: Point
        let hs = t.font.horizontalSpacing
        t.font.horizontalSpacing = t.trackingAmount
        if t.justification != tjLeft:
            var textSize = t.font.sizeOfString(t.text)
            if t.justification == tjCenter:
                p.x -= textSize.width / 2
            else:
                p.x -= textSize.width

        p.y -= t.font.size

        c.drawText(t.font, p, t.text)
        t.font.horizontalSpacing = hs

method animatableProperty1*(t: Text, name: string): proc (v: Coord) =
    case name
    of "Tracking Amount": result = proc (v: Coord) =
        t.trackingAmount = v
    else: result = nil

method visitProperties*(t: Text, p: var PropertyVisitor) =
    p.visitProperty("text", t.text)
    p.visitProperty("color", t.color)

registerComponent[Text]()
