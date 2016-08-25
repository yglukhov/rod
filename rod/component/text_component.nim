import json
import nimx.types
import nimx.font
import nimx.context
import nimx.view
import nimx.property_visitor
import nimx.portable_gl

import rod.node
import rod.component
import rod.component.camera
import rod.viewport
import rod.tools.serializer
import rod.material.shader

const gradientAndStrokeVS = """
attribute vec4 aPosition;

#ifdef GRADIENT_ENABLED
    uniform float point_y;
    uniform float size_y;
    varying float vGradient;
#endif

uniform mat4 modelViewProjectionMatrix;
varying vec2 vTexCoord;

void main() {
    vTexCoord = aPosition.zw;
    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xy, 0, 1);

#ifdef GRADIENT_ENABLED
    vGradient = (aPosition.y - point_y) / size_y;
#endif
}
"""

const gradientAndStrokePS = """
#ifdef GL_ES
    #extension GL_OES_standard_derivatives : enable
    precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 fillColor;

#ifdef STROKE_ENABLED
    uniform float strokeSize;
#endif

#ifdef GRADIENT_ENABLED
    uniform vec4 colorFrom;
    uniform vec4 colorTo;
    varying float vGradient;
#endif

varying vec2 vTexCoord;

float thresholdFunc(float glyphScale)
{
    float base = 0.5;
    float baseDev = 0.065;
    float devScaleMin = 0.15;
    float devScaleMax = 0.3;
    return base - ((clamp(glyphScale, devScaleMin, devScaleMax) - devScaleMin) / (devScaleMax - devScaleMin) * -baseDev + baseDev);
}

float spreadFunc(float glyphScale)
{
    return 0.06 / glyphScale;
}

void main()
{
    float scale = (1.0 / 320.0) / fwidth(vTexCoord.x);
    scale = abs(scale);
#ifdef STROKE_ENABLED
    float aBase = thresholdFunc(scale) - strokeSize;
#else
    float aBase = thresholdFunc(scale);
#endif
    float aRange = spreadFunc(scale);
    float aMin = max(0.0, aBase - aRange);
    float aMax = min(aBase + aRange, 1.0);

    float dist = texture2D(texUnit, vTexCoord).a;
    float alpha = smoothstep(aMin, aMax, dist);

#ifdef GRADIENT_ENABLED
    vec4 color = mix(colorFrom, colorTo, vGradient);
    gl_FragColor = vec4(color.rgb, alpha * color.a);
#else
    gl_FragColor = vec4(fillColor.rgb, alpha * fillColor.a);
#endif
}
"""

type TextJustification* = enum
    tjLeft
    tjCenter
    tjRight

type Text* = ref object of Component
    mText*: string
    mTextSize*: Size
    color*: Color
    font*: Font
    trackingAmount*: Coord
    justification*: TextJustification
    shadowX*, shadowY*: Coord
    shadowColor*: Color
    isColorGradient*: bool
    colorFrom*: Color
    colorTo*: Color

    gradientAndStrokeShader*: Shader
    strokeSize*: float
    strokeColor*: Color
    fontFace*: string
    isStrokeGradient*: bool
    strokeColorFrom*: Color
    strokeColorTo*: Color

method init*(t: Text) =
    t.color = blackColor()
    t.font = systemFont()
    t.shadowColor = newGrayColor(0.0, 0.5)

    t.gradientAndStrokeShader = newShader(gradientAndStrokeVS, gradientAndStrokePS,
        @[(0.GLuint, "aPosition")])

    t.colorFrom = whiteColor()
    t.colorTo = blackColor()
    t.strokeColorFrom = whiteColor()
    t.strokeColorTo = blackColor()

proc `text=`*(t: Text, text: string) =
    t.mText = text
    t.mTextSize = t.font.sizeOfString(t.mText)
    if not t.node.isNil and not t.node.sceneView.isNil:
        t.node.sceneView.setNeedsDisplay()

proc text*(t: Text) : string =
    result = t.mText

method deserialize*(t: Text, j: JsonNode, s: Serializer) =
    var font_size: float
    var v = j{"fontSize"}
    if not v.isNil:
        font_size = v.getFNum()

    v = j{"font"}
    if not v.isNil:
        t.fontFace = v.getStr()
        t.font = newFontWithFace(t.fontFace, font_size)
        if t.font.isNil:
            echo "font = ", t.fontFace, "  doesn't load"
    elif font_size > 0:
        t.font = systemFontOfSize(font_size)

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

    v = j{"justification"}
    if not v.isNil:
        case v.getStr()
        of "left": t.justification = tjLeft
        of "center": t.justification = tjCenter
        of "right": t.justification = tjRight
        else: discard

    s.deserializeValue(j, "text", t.text)
    s.deserializeValue(j, "shadowX", t.shadowX)
    s.deserializeValue(j, "shadowY", t.shadowY)
    s.deserializeValue(j, "strokeSize", t.strokeSize)
    s.deserializeValue(j, "strokeColor", t.strokeColor)

    s.deserializeValue(j, "isColorGradient", t.isColorGradient)
    s.deserializeValue(j, "colorFrom", t.colorFrom)
    s.deserializeValue(j, "colorTo", t.colorTo)
    s.deserializeValue(j, "isStrokeGradient", t.isStrokeGradient)
    s.deserializeValue(j, "strokeColorFrom", t.strokeColorFrom)
    s.deserializeValue(j, "strokeColorTo", t.strokeColorTo)

method serialize*(c: Text, s: Serializer): JsonNode =
    result = newJObject()
    result.add("text", s.getValue(c.text))
    result.add("color", s.getValue(c.color))
    result.add("shadowX", s.getValue(c.shadowX))
    result.add("shadowY", s.getValue(c.shadowY))
    result.add("shadowColor", s.getValue(c.shadowColor))
    result.add("Tracking Amount", s.getValue(c.trackingAmount))
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

proc drawShadow(t: Text, point: Point) =
    let c = currentContext()
    var p = point

    c.fillColor = t.shadowColor
    let px = p.x
    let py = p.y

    let sv = newVector3(t.shadowX, t.shadowY)
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

    p.x = px + wsv.x / abs(worldScale.x)
    p.y = py - y_direction * wsv.y / abs(worldScale.y)
    c.drawText(t.font, p, t.mText)

proc drawStroke(t: Text, point: Point) =
    let c = currentContext()
    let gl = c.gl
    var p = point

    t.gradientAndStrokeShader.addDefine("STROKE_ENABLED")
    if t.isStrokeGradient:
        t.gradientAndStrokeShader.addDefine("GRADIENT_ENABLED")
    else:
        t.gradientAndStrokeShader.removeDefine("GRADIENT_ENABLED")
    t.gradientAndStrokeShader.bindShader()

    t.gradientAndStrokeShader.setUniform("fillColor", t.strokeColor)
    t.gradientAndStrokeShader.setUniform("strokeSize", t.strokeSize / 15)
    t.gradientAndStrokeShader.setTransformUniform()

    if t.isStrokeGradient:
        t.gradientAndStrokeShader.setUniform("point_y", point.y)
        t.gradientAndStrokeShader.setUniform("size_y", t.mTextSize.height)
        t.gradientAndStrokeShader.setUniform("colorFrom", t.strokeColorFrom)
        t.gradientAndStrokeShader.setUniform("colorTo", t.strokeColorTo)

    gl.activeTexture(gl.TEXTURE0)
    t.gradientAndStrokeShader.setUniform("texUnit", 0)

    c.drawTextBase(t.font, p, t.mText)

proc drawMyText(t: Text, point: Point) =
    let c = currentContext()
    let gl = c.gl
    var p = point
    if t.isColorGradient == false:
        c.drawText(t.font, p, t.mText)
        return

    t.gradientAndStrokeShader.removeDefine("STROKE_ENABLED")
    t.gradientAndStrokeShader.addDefine("GRADIENT_ENABLED")
    t.gradientAndStrokeShader.bindShader()

    t.gradientAndStrokeShader.setUniform("fillColor", t.color)
    t.gradientAndStrokeShader.setTransformUniform()

    t.gradientAndStrokeShader.setUniform("point_y", point.y)
    t.gradientAndStrokeShader.setUniform("size_y", t.mTextSize.height)
    t.gradientAndStrokeShader.setUniform("colorFrom", t.colorFrom)
    t.gradientAndStrokeShader.setUniform("colorTo", t.colorTo)

    gl.activeTexture(gl.TEXTURE0)
    t.gradientAndStrokeShader.setUniform("texUnit", 0)

    c.drawTextBase(t.font, p, t.mText)

method draw*(t: Text) =
    if not t.mText.isNil:
        let c = currentContext()
        var p: Point
        let oldBaseline = t.font.baseline
        t.font.baseline = bAlphabetic
        let hs = t.font.horizontalSpacing
        t.font.horizontalSpacing = t.trackingAmount
        if t.justification != tjLeft:
            var textSize = t.mTextSize
            if t.justification == tjCenter:
                p.x -= textSize.width / 2
            else:
                p.x -= textSize.width

        if t.strokeSize > 0:
            t.drawStroke(p)

        if t.shadowX != 0 or t.shadowY != 0:
            t.drawShadow(p)

        c.fillColor = t.color
        t.drawMyText(p)
        t.font.horizontalSpacing = hs
        t.font.baseline = oldBaseline

method visitProperties*(t: Text, p: var PropertyVisitor) =
    p.visitProperty("text", t.text)
    p.visitProperty("color", t.color)
    p.visitProperty("shadowX", t.shadowX)
    p.visitProperty("shadowY", t.shadowY)
    p.visitProperty("shadowColor", t.shadowColor)
    p.visitProperty("Tracking Amount", t.trackingAmount)

    p.visitProperty("isColorGradient", t.isColorGradient)
    p.visitProperty("colorFrom", t.colorFrom)
    p.visitProperty("colorTo", t.colorTo)

    p.visitProperty("strokeSize", t.strokeSize)
    p.visitProperty("strokeColor", t.strokeColor)
    p.visitProperty("isStrokeGradient", t.isStrokeGradient)
    p.visitProperty("strokeColorFrom", t.strokeColorFrom)
    p.visitProperty("strokeColorTo", t.strokeColorTo)

registerComponent[Text]()
