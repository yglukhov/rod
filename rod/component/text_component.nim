import json
import nimx.types
import nimx.font
import nimx.context
import nimx.view

import rod.node
import rod.component
import rod.property_visitor

type TextJustification* = enum
    tjLeft
    tjCenter
    tjRight

type Text* = ref object of Component
    mText*: string
    color*: Color
    font*: Font
    trackingAmount*: Coord
    justification*: TextJustification
    shadowX*, shadowY*: Coord
    shadowColor*: Color

method init*(t: Text) =
    t.color = blackColor()
    t.font = systemFont()
    t.shadowColor = newGrayColor(0.0, 0.5)

proc `text=`*(t: Text, text: string) =
    t.mText = text
    if not t.node.isNil and not t.node.sceneView.isNil:
        t.node.sceneView.setNeedsDisplay()

proc text*(t: Text) : string =
    result = t.mText

method deserialize*(t: Text, j: JsonNode) =
    var v = j{"text"}
    if not v.isNil:
        t.mText = v.getStr()

    v = j{"color"}
    if not v.isNil:
        t.color = newColor(v[0].getFnum(), v[1].getFnum(), v[2].getFnum())
        if v.len > 3: # Deprecated
            t.node.alpha = v[3].getFnum()

    v = j{"shadowOff"}
    if not v.isNil:
        t.shadowX = v[0].getFnum()
        t.shadowY = v[1].getFnum()

    v = j{"shadowColor"}
    if not v.isNil:
        t.shadowColor = newColor(v[0].getFnum(), v[1].getFnum(), v[2].getFnum(), v[3].getFnum())

    v = j{"fontSize"}
    if not v.isNil:
        t.font = systemFontOfSize(v.getFNum())

    v = j{"justification"}
    if not v.isNil:
        case v.getStr()
        of "left": t.justification = tjLeft
        of "center": t.justification = tjCenter
        of "right": t.justification = tjRight
        else: discard

method draw*(t: Text) =
    if not t.mText.isNil:
        let c = currentContext()
        var p: Point
        let hs = t.font.horizontalSpacing
        t.font.horizontalSpacing = t.trackingAmount
        if t.justification != tjLeft:
            var textSize = t.font.sizeOfString(t.mText)
            if t.justification == tjCenter:
                p.x -= textSize.width / 2
            else:
                p.x -= textSize.width

        p.y -= t.font.size

        if t.shadowX != 0 or t.shadowY != 0:
            c.fillColor = t.shadowColor
            let px = p.x
            let py = p.y

            let sv = newVector3(t.shadowX, t.shadowY)
            var wsv = t.node.localToWorld(sv)
            let wo = t.node.localToWorld(newVector3())
            wsv -= wo
            wsv.normalize()
            wsv *= sv.length

            p.x = px + wsv.x
            p.y = py + wsv.y
            c.drawText(t.font, p, t.mText)
            p.x = px
            p.y = py

        c.fillColor = t.color
        c.drawText(t.font, p, t.mText)
        t.font.horizontalSpacing = hs

method visitProperties*(t: Text, p: var PropertyVisitor) =
    p.visitProperty("text", t.text)
    p.visitProperty("color", t.color)
    p.visitProperty("shadowX", t.shadowX)
    p.visitProperty("shadowY", t.shadowY)
    p.visitProperty("shadowColor", t.shadowColor)
    p.visitProperty("Tracking Amount", t.trackingAmount)

registerComponent[Text]()
