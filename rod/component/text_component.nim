import json
import nimx.types
import nimx.font
import nimx.context
import nimx.view
import nimx.property_visitor
import nimx.portable_gl
import nimx.formatted_text
import nimx.private.font.font_data

import rod.rod_types
import rod.node
import rod.component
import rod.component.camera
import rod.viewport
import rod.tools.serializer
import rod.tools.debug_draw
import rod.utils.attributed_text
import rod / utils / [ property_desc, serialization_codegen ]

export formatted_text

type
    Text* = ref object of Component
        mText*: FormattedText
        mBoundingOffset: Point

Text.properties:
    text(phantom = string)
    font(phantom = string)
    fontSize(phantom = float32)
    color(phantom = Color)
    color2(phantom = Color)
    shadowOff(phantom = Size)
    shadowColor(phantom = Color)
    shadowSpread(phantom = float32)
    shadowRadius(phantom = float32)

    strokeSize(phantom = float32)
    strokeColor(phantom = Color)
    strokeColor2(phantom = Color)

    bounds(phantom = Rect)
    lineSpacing(phantom = float32)
    horizontalAlignment:
        phantom: HorizontalTextAlignment
        serializationKey: "justification"
    verticalAlignment(phantom = VerticalAlignment)
    isColorGradient(phantom = bool)
    isStrokeGradient(phantom = bool)

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
            fontSize = v.getFloat()

        v = j{"font"}
        var font: Font
        if not v.isNil:
            let fontFace = v.getStr()
            font = newFontWithFace(fontFace, fontSize)
            if font.isNil:
                echo "font = ", fontFace, "  doesn't load, system font will be used"
                font = systemFontOfSize(fontSize)
        elif font_size > 0:
            font = systemFontOfSize(fontSize)
        t.mText.setFontInRange(0, -1, font)

        v = j{"color"}
        if not v.isNil:
            let color = newColor(v[0].getFloat(), v[1].getFloat(), v[2].getFloat())
            t.mText.setTextColorInRange(0, -1, color)
            if v.len > 3: # Deprecated
                t.node.alpha = v[3].getFloat()

        v = j{"shadowOff"}
        var shadowX, shadowY: float  # TODO do only one format
        if not v.isNil:
            shadowX = v[0].getFloat()
            shadowY = v[1].getFloat()
        else:
            s.deserializeValue(j, "shadowX", shadowX)
            s.deserializeValue(j, "shadowY", shadowY)

        var isShadowExist = false
        if shadowX > 0.0 or shadowY > 0.0: isShadowExist = true

        elif "shadowX" in j and "shadowY" in j:
            shadowY = j["shadowY"].getFloat()
            shadowX = j["shadowX"].getFloat()

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
            t.mBoundingOffset = newPoint(v[0].getFloat(), v[1].getFloat())
            t.mText.boundingSize = newSize(v[2].getFloat(), v[3].getFloat())

        t.mText.processAttributedText()
################################################################################
# Old compatibility api
proc color*(c: Text): Color = c.mText.colorOfRuneAtPos(0).color1
proc `color=`*(c: Text, v: Color) = c.mText.setTextColorInRange(0, -1, v)

proc shadowOffset*(c: Text): Size = c.mText.shadowOfRuneAtPos(0).offset
proc `shadowOffset=`*(c: Text, v: Size) =
    var s = c.mText.shadowOfRuneAtPos(0)
    s.offset = v
    c.mText.setShadowInRange(0, -1, s.color, s.offset, s.radius, s.spread)

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
    c.mText.setFontInRange(0, -1, v)

proc fontSize*(c: Text): float32 = c.mText.fontOfRuneAtPos(0).size
proc `fontSize=`*(c: Text, v: float32) =
    let f = c.font
    c.mText.setFontInRange(0, -1, newFontWithFace(f.face, v))

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

    let fontFace = c.font().face
    if fontFace != systemFont().face:
        result.add("font", s.getValue(fontFace))
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

proc toPhantom(c: Text, p: var object) =
    p.text = c.mText.text

    let fontFace = c.font().face
    if fontFace != systemFont().face:
        p.font = fontFace

    let fs = c.fontSize
    if fs != systemFontSize():
        p.fontSize = fs

    p.isColorGradient = c.isColorGradient
    if p.isColorGradient:
        p.color = c.colorFrom
        p.color2 = c.colorTo
    else:
        p.color = c.color

    p.shadowOff = c.shadowOffset
    p.shadowColor = c.shadowColor
    p.shadowSpread = c.shadowSpread
    p.shadowRadius = c.shadowRadius

    p.strokeSize = c.strokeSize
    p.isStrokeGradient = c.isStrokeGradient
    if p.isStrokeGradient:
        p.strokeColor = c.strokeColorFrom
        p.strokeColor2 = c.strokeColorTo
    else:
        p.strokeColor = c.strokeColor

    p.bounds.origin = c.mBoundingOffset
    p.bounds.size = c.mText.boundingSize

    p.lineSpacing = c.lineSpacing
    p.horizontalAlignment = c.mText.horizontalAlignment
    p.verticalAlignment = c.mText.verticalAlignment

proc fromPhantom(c: Text, p: object) =
    c.mText.text = p.text

    var fontSize = p.fontSize
    if fontSize == 0: fontSize = systemFontSize()

    var font: Font
    if p.font.len != 0:
        font = newFontWithFace(p.font, fontSize)

    if font.isNil:
        font = systemFontOfSize(fontSize)

    font.face = p.font # Hack for bin format conversion. Should be fixed somehow?

    c.mText.setFontInRange(0, -1, font)

    if p.isColorGradient:
        c.mText.setTextColorInRange(0, -1, p.color, p.color2)
    else:
        c.mText.setTextColorInRange(0, -1, p.color)

    if p.shadowColor.a > 0 or p.shadowRadius > 0 or p.shadowSpread > 0:
        c.mText.setShadowInRange(0, -1, p.shadowColor, p.shadowOff, p.shadowRadius, p.shadowSpread)

    if p.strokeSize > 0:
        if p.isStrokeGradient:
            c.mText.setStrokeInRange(0, -1, p.strokeColor, p.strokeColor2, p.strokeSize)
        else:
            c.mText.setStrokeInRange(0, -1, p.strokeColor, p.strokeSize)

    if p.bounds != zeroRect:
        c.mBoundingOffset = p.bounds.origin
        c.mText.boundingSize = p.bounds.size

    c.mText.lineSpacing = p.lineSpacing

    c.mText.horizontalAlignment = p.horizontalAlignment
    c.mText.verticalAlignment = p.verticalAlignment

genSerializationCodeForComponent(Text)

method getBBox*(t: Text): BBox =
    var height = t.mText.totalHeight()
    var width = t.mText.totalWidth()
    var offsetTop = t.mText.topOffset() + t.mBoundingOffset.y
    var offsetLeft = t.mBoundingOffset.x

    if t.mText.boundingSize.width == 0:
        offsetTop -= t.mText.lineBaseline(0)

        case t.mText.horizontalAlignment:
            of haLeft, haJustify:
                discard
            of haCenter:
                offsetLeft -= width / 2
            of haRight:
                offsetLeft -= width
    else:
        if t.mText.truncationBehavior != tbNone or t.mText.boundingSize.height > height:
            height = t.mText.boundingSize.height

        if t.mText.truncationBehavior != tbNone:
            width = t.mText.boundingSize.width
        else:
            if t.mText.boundingSize.width > width:
                width = t.mText.boundingSize.width
            else:
                case t.mText.horizontalAlignment:
                    of haLeft, haJustify:
                        discard
                    of haCenter:
                        offsetLeft -= (width - t.mText.boundingSize.width) / 2
                    of haRight:
                        offsetLeft -= width - t.mText.boundingSize.width

    result.maxPoint = newVector3(width + offsetLeft, height + offsetTop, 0.0)
    result.minPoint = newVector3(offsetLeft, offsetTop, 0.0)

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
    p.visitProperty("shadowOff", t.shadowOffset)
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
