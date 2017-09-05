import json
import nimx.types
import nimx.font
import nimx.context
import nimx.view
import nimx.property_visitor
import nimx.portable_gl
import nimx.formatted_text
import nimx.private.font.font_data

import rod.node
import rod.component
import rod.component.camera
import rod.viewport
import rod.tools.serializer
import rod.tools.debug_draw
import rod.utils.attributed_text

export formatted_text

type TextJustification* = enum
    tjLeft
    tjCenter
    tjRight

type Text* = ref object of Component
    mText*: FormattedText
    mBoundingOffset: Point
    fontFace*: string

method init*(t: Text) =
    procCall t.Component.init()
    t.mText = newFormattedText()

proc `text=`*(t: Text, text: string) =
    t.mText.text = text
    t.mText.processAttributedText()
    if not t.node.isNil and not t.node.sceneView.isNil:
        t.node.sceneView.setNeedsDisplay()

proc `boundingSize=`*(t: Text, boundingSize: Size) =
    t.mText.boundingSize = boundingSize

proc `truncationBehavior=`*(t: Text, b: TruncationBehavior) =
    t.mText.truncationBehavior = b

proc `horizontalAlignment=`*(t: Text, horizontalAlignment: HorizontalTextAlignment) =
    t.mText.horizontalAlignment = horizontalAlignment

proc `verticalAlignment=`*(t: Text, verticalAlignment: VerticalAlignment) =
    t.mText.verticalAlignment = verticalAlignment

proc text*(t: Text) : string =
    result = t.mText.text

method deserialize*(t: Text, j: JsonNode, s: Serializer) =
    var v = j{"text"}
    if not v.isNil and v.kind == JString:
        t.mText.text = v.str

    if v.isNil or v.kind == JString:
        var fontSize: float
        v = j{"fontSize"}
        if not v.isNil:
            fontSize = v.getFNum()

        v = j{"font"}
        var font: Font
        if not v.isNil:
            t.fontFace = v.getStr()
            font = newFontWithFace(t.fontFace, fontSize)
            if font.isNil:
                echo "font = ", t.fontFace, "  doesn't load, system font will be used"
                font = systemFontOfSize(fontSize)
        elif font_size > 0:
            font = systemFontOfSize(fontSize)
        t.mText.setFontInRange(0, -1, font)

        v = j{"color"}
        if not v.isNil:
            let color = newColor(v[0].getFnum(), v[1].getFnum(), v[2].getFnum())
            t.mText.setTextColorInRange(0, -1, color)
            if v.len > 3: # Deprecated
                t.node.alpha = v[3].getFnum()

        v = j{"shadowOff"}
        var shadowX, shadowY: float  # TODO do only one format
        if not v.isNil:
            shadowX = v[0].getFnum()
            shadowY = v[1].getFnum()
        else:
            s.deserializeValue(j, "shadowX", shadowX)
            s.deserializeValue(j, "shadowY", shadowY)

        var isShadowExist = false
        if shadowX > 0.0 or shadowY > 0.0: isShadowExist = true

        elif "shadowX" in j and "shadowY" in j:
            shadowY = j["shadowY"].getFnum()
            shadowX = j["shadowX"].getFnum()

        v = j{"shadowColor"}
        var shadowColor: Color
        s.deserializeValue(j, "shadowColor", shadowColor)
        if shadowColor.a > 0.0: isShadowExist = true

        var shadowSpread: float32
        s.deserializeValue(j, "shadowSpread", shadowSpread)
        if shadowSpread > 0.0: isShadowExist = true

        var shadowRadius: float32
        s.deserializeValue(j, "shadowRadius", shadowRadius)
        if shadowRadius > 0.0: isShadowExist = true

        if isShadowExist:
            t.mText.setShadowInRange(0, -1, shadowColor, newSize(shadowX, shadowY), shadowRadius, shadowSpread)

        v = j{"justification"}
        var horAlign = haLeft
        if not v.isNil:
            case v.getStr()
            of "left", "haLeft": horAlign = haLeft
            of "center", "haCenter": horAlign = haCenter
            of "right", "haRight": horAlign = haRight
            else: discard

        t.mText.horizontalAlignment = horAlign

        v = j{"verticalAlignment"}
        var vertAlign = vaTop
        if not v.isNil:
            case v.getStr()
            of "top", "vaTop": vertAlign = vaTop
            of "center", "vaCenter": vertAlign = vaCenter
            of "bottom", "vaBottom": vertAlign = vaBottom
            else: discard

        t.mText.verticalAlignment = vertAlign

        var strokeSize: float
        s.deserializeValue(j, "strokeSize", strokeSize)
        if strokeSize != 0:
            var isStrokeGradient: bool
            s.deserializeValue(j, "isStrokeGradient", isStrokeGradient)
            if isStrokeGradient:
                var color1: Color
                var color2: Color
                s.deserializeValue(j, "strokeColorFrom", color1)
                s.deserializeValue(j, "strokeColorTo", color2)
                t.mText.setStrokeInRange(0, -1, color1, color2, strokeSize)
            else:
                var color: Color
                s.deserializeValue(j, "strokeColor", color)
                t.mText.setStrokeInRange(0, -1, color, strokeSize)

        var ls : float32
        s.deserializeValue(j, "lineSpacing", ls)
        t.mText.lineSpacing = ls

        var isColorGradient: bool
        s.deserializeValue(j, "isColorGradient", isColorGradient)
        if isColorGradient:
            var color1: Color
            var color2: Color
            s.deserializeValue(j, "colorFrom", color1)
            s.deserializeValue(j, "colorTo", color2)
            t.mText.setTextColorInRange(0, -1, color1, color2)

        v = j{"bounds"}
        if not v.isNil:
            let attr = newPoint(font.getCharComponent(t.text, GlyphMetricsComponent.compX), font.getCharComponent(t.text, GlyphMetricsComponent.compY))
            t.mBoundingOffset = newPoint(v[0].getFNum() - attr.x * font.scale, v[1].getFNum() - attr.y * font.scale)
            t.mText.boundingSize = newSize(v[2].getFNum(), v[3].getFNum())

        t.mText.processAttributedText()
################################################################################
# Old compatibility api
proc color*(c: Text): Color = c.mText.colorOfRuneAtPos(0).color1
proc `color=`*(c: Text, v: Color) = c.mText.setTextColorInRange(0, -1, v)

proc shadowX*(c: Text): float32 = c.mText.shadowOfRuneAtPos(0).offset.width
proc shadowY*(c: Text): float32 = c.mText.shadowOfRuneAtPos(0).offset.height

proc `shadowX=`*(c: Text, v: float32) =
    var s = c.mText.shadowOfRuneAtPos(0)
    s.offset.width = v
    c.mText.setShadowInRange(0, -1, s.color, s.offset, s.radius, s.spread)

proc `shadowY=`*(c: Text, v: float32) =
    var s = c.mText.shadowOfRuneAtPos(0)
    s.offset.height = v
    c.mText.setShadowInRange(0, -1, s.color, s.offset, s.radius, s.spread)

proc shadowColor*(c: Text): Color = c.mText.shadowOfRuneAtPos(0).color
proc `shadowColor=`*(c: Text, v: Color) =
    var s = c.mText.shadowOfRuneAtPos(0)
    s.color = v
    c.mText.setShadowInRange(0, -1, s.color, s.offset, s.radius, s.spread)

proc shadowRadius*(c: Text): float32 = c.mText.shadowOfRuneAtPos(0).radius
proc `shadowRadius=`*(c: Text, r: float32) =
    var s = c.mText.shadowOfRuneAtPos(0)
    s.radius = r
    c.mText.setShadowInRange(0, -1, s.color, s.offset, s.radius, s.spread)

proc shadowSpread*(c: Text): float32 = c.mText.shadowOfRuneAtPos(0).spread
proc `shadowSpread=`*(c: Text, spread: float32) =
    var s = c.mText.shadowOfRuneAtPos(0)
    s.spread = spread
    c.mText.setShadowInRange(0, -1, s.color, s.offset, s.radius, s.spread)

proc font*(c: Text): Font = c.mText.fontOfRuneAtPos(0)
proc `font=`*(c: Text, v: Font) =
    c.fontFace = v.face
    c.mText.setFontInRange(0, -1, v)

proc fontSize*(c: Text): float32 = c.mText.fontOfRuneAtPos(0).size
proc `fontSize=`*(c: Text, v: float32) =
    var font: Font
    if c.fontFace.isNil:
        font = systemFontOfSize(v)
    else:
        font = newFontWithFace(c.fontFace, v)
    c.mText.setFontInRange(0, -1, font)

proc trackingAmount*(c: Text): float32 = c.mText.trackingOfRuneAtPos(0)
proc `trackingAmount=`*(c: Text, v: float32) = c.mText.setTrackingInRange(0, -1, v)

proc strokeSize*(c: Text): float32 = c.mText.strokeOfRuneAtPos(0).size
proc `strokeSize=`*(c: Text, v: float32) =
    var s = c.mText.strokeOfRuneAtPos(0)
    s.size = v
    if s.isGradient:
        c.mText.setStrokeInRange(0, -1, s.color1, s.color2, s.size)
    else:
        c.mText.setStrokeInRange(0, -1, s.color1, s.size)

proc strokeColor*(c: Text): Color = c.mText.strokeOfRuneAtPos(0).color1
proc `strokeColor=`*(c: Text, v: Color) =
    var s = c.mText.strokeOfRuneAtPos(0)
    s.color1 = v
    c.mText.setStrokeInRange(0, -1, s.color1, s.size)

proc strokeColorFrom*(c: Text): Color = c.mText.strokeOfRuneAtPos(0).color1
proc `strokeColorFrom=`*(c: Text, v: Color) =
    var s = c.mText.strokeOfRuneAtPos(0)
    s.color1 = v
    c.mText.setStrokeInRange(0, -1, s.color1, s.color2, s.size)

proc strokeColorTo*(c: Text): Color = c.mText.strokeOfRuneAtPos(0).color2
proc `strokeColorTo=`*(c: Text, v: Color) =
    var s = c.mText.strokeOfRuneAtPos(0)
    s.color2 = v
    c.mText.setStrokeInRange(0, -1, s.color1, s.color2, s.size)

proc isStrokeGradient*(c: Text): bool = c.mText.strokeOfRuneAtPos(0).isGradient
proc `isStrokeGradient=`*(c: Text, v: bool) =
    var s = c.mText.strokeOfRuneAtPos(0)
    if v:
        c.mText.setStrokeInRange(0, -1, s.color1, s.color2, s.size)
    else:
        c.mText.setStrokeInRange(0, -1, s.color1, s.size)

proc isColorGradient*(c: Text): bool = c.mText.colorOfRuneAtPos(0).isGradient
proc `isColorGradient=`*(c: Text, v: bool) =
    var s = c.mText.colorOfRuneAtPos(0)
    if v:
        c.mText.setTextColorInRange(0, -1, s.color1, s.color2)
    else:
        c.mText.setTextColorInRange(0, -1, s.color1)

proc colorFrom*(c: Text): Color = c.mText.colorOfRuneAtPos(0).color1
proc `colorFrom=`*(c: Text, v: Color) =
    var s = c.mText.colorOfRuneAtPos(0)
    s.color1 = v
    c.mText.setTextColorInRange(0, -1, s.color1, s.color2)

proc colorTo*(c: Text): Color = c.mText.colorOfRuneAtPos(0).color2
proc `colorTo=`*(c: Text, v: Color) =
    var s = c.mText.colorOfRuneAtPos(0)
    s.color2 = v
    c.mText.setTextColorInRange(0, -1, s.color1, s.color2)

proc lineSpacing*(c: Text): Coord = c.mText.lineSpacing
proc `lineSpacing=`*(c: Text, s: float32) = c.mText.lineSpacing = s

method serialize*(c: Text, s: Serializer): JsonNode =
    result = newJObject()
    result.add("text", s.getValue(c.text))
    result.add("color", s.getValue(c.color))
    result.add("shadowX", s.getValue(c.shadowX))
    result.add("shadowY", s.getValue(c.shadowY))
    result.add("shadowRadius", s.getValue(c.shadowRadius))
    result.add("shadowSpread", s.getValue(c.shadowSpread))
    result.add("shadowColor", s.getValue(c.shadowColor))
    result.add("Tracking Amount", s.getValue(c.trackingAmount))
    result.add("lineSpacing", s.getValue(c.lineSpacing))
    result.add("fontSize", s.getValue(c.font.size))

    if not c.fontFace.isNil:
        result.add("font", s.getValue(c.fontFace))
    result.add("strokeSize", s.getValue(c.strokeSize))
    result.add("strokeColor", s.getValue(c.strokeColor))

    result.add("isColorGradient", s.getValue(c.isColorGradient))
    result.add("colorFrom", s.getValue(c.colorFrom))
    result.add("colorTo", s.getValue(c.colorTo))
    result.add("isStrokeGradient", s.getValue(c.isStrokeGradient))
    result.add("strokeColorFrom", s.getValue(c.strokeColorFrom))
    result.add("strokeColorTo", s.getValue(c.strokeColorTo))

    result.add("bounds", s.getValue([c.mBoundingOffset.x, c.mBoundingOffset.y, c.mText.boundingSize.width, c.mText.boundingSize.height]))

    var horAlign = "haLeft"
    case c.mText.horizontalAlignment
    of haLeft: horAlign = "haLeft"
    of haCenter: horAlign = "haCenter"
    of haRight: horAlign = "haRight"
    else: discard
    result.add("justification", s.getValue(horAlign))

    var vertAlign = "vaTop"
    case c.mText.verticalAlignment
    of vaTop: vertAlign = "vaTop"
    of vaCenter: vertAlign = "vaCenter"
    of vaBottom: vertAlign = "vaBottom"
    else: discard
    result.add("verticalAlignment", s.getValue(vertAlign))

proc shadowMultiplier(t: Text): Size =
    let sv = newVector3(1, 1)
    var wsv = t.node.localToWorld(sv)
    let wo = t.node.localToWorld(newVector3())
    wsv -= wo
    wsv.normalize()
    wsv *= sv.length

    var worldScale = newVector3(1.0)
    var worldRotation: Vector4
    discard t.node.worldTransform.tryGetScaleRotationFromModel(worldScale, worldRotation)

    let view = t.node.sceneView
    var projMatrix : Matrix4
    view.camera.getProjectionMatrix(view.bounds, projMatrix)
    let y_direction = abs(projMatrix[5]) / projMatrix[5]

    result = newSize(wsv.x / abs(worldScale.x), - y_direction * wsv.y / abs(worldScale.y))

proc debugDraw(t: Text) =
    DDdrawRect(newRect(t.mBoundingOffset, t.mText.boundingSize))

method draw*(t: Text) =
    if not t.mText.isNil:
        let c = currentContext()
        var p = t.mBoundingOffset
        if t.mText.boundingSize.width == 0:
            # This is an unbound point text. Origin is at the baseline of the
            # first line.
            p.y -= t.mText.lineBaseline(0)
        if t.mText.hasShadow:
            t.mText.shadowMultiplier = t.shadowMultiplier
        c.drawText(p, t.mText)

        if t.node.sceneView.editing:
            t.debugDraw()

method visitProperties*(t: Text, p: var PropertyVisitor) =
    p.visitProperty("text", t.text)
    p.visitProperty("fontSize", t.fontSize)
    p.visitProperty("font", t.font)
    p.visitProperty("color", t.color)
    p.visitProperty("shadowX", t.shadowX)
    p.visitProperty("shadowY", t.shadowY)
    p.visitProperty("shadowRadius", t.shadowRadius)
    p.visitProperty("shadowSpread", t.shadowSpread)
    p.visitProperty("shadowColor", t.shadowColor)
    p.visitProperty("Tracking Amount", t.trackingAmount)
    p.visitProperty("lineSpacing", t.lineSpacing)

    p.visitProperty("isColorGradient", t.isColorGradient)
    p.visitProperty("colorFrom", t.colorFrom)
    p.visitProperty("colorTo", t.colorTo)

    p.visitProperty("strokeSize", t.strokeSize)
    p.visitProperty("strokeColor", t.strokeColor)
    p.visitProperty("isStrokeGradient", t.isStrokeGradient)
    p.visitProperty("strokeColorFrom", t.strokeColorFrom)
    p.visitProperty("strokeColorTo", t.strokeColorTo)

    p.visitProperty("boundingOffset", t.mBoundingOffset)
    p.visitProperty("boundingSize", t.mText.boundingSize)
    p.visitProperty("horAlignment", t.mText.horizontalAlignment)
    p.visitProperty("vertAlignment", t.mText.verticalAlignment)
    p.visitProperty("truncationBehavior", t.mText.truncationBehavior)

registerComponent(Text)
