import json

import nimx.view
import nimx.context
import nimx.matrixes
import nimx.composition
import nimx.portable_gl
import nimx.property_visitor

import rod.node
import rod.viewport
import rod.component
import rod.tools.serializer
import rod / utils / [ property_desc, serialization_codegen ]

var effectLinearLocal = newPostEffect("""
void grad_fill_effect_linear_local(vec2 gradientStartPos, vec2 gradientEndPos, vec4 startColor, vec4 endColor) {
    float  alpha = atan( -gradientEndPos.y + gradientStartPos.y, gradientEndPos.x - gradientStartPos.x );
    float  gradientStartPosRotatedX = gradientStartPos.x*cos(alpha) - gradientStartPos.y*sin(alpha);
    float  gradientEndPosRotatedX   = gradientEndPos.x*cos(alpha) - gradientEndPos.y*sin(alpha);
    float  d = gradientEndPosRotatedX - gradientStartPosRotatedX;
    float y = vPos.y;
    float x = vPos.x;
    float xLocRotated = x*cos( alpha ) - y*sin( alpha );
    vec4 gradientColor = mix(startColor, endColor, smoothstep( gradientStartPosRotatedX, gradientStartPosRotatedX + d, xLocRotated ) );

    gl_FragColor.rgb = mix(gl_FragColor, gradientColor, gradientColor.a).rgb;
}
""", "grad_fill_effect_linear_local", ["vec2", "vec2", "vec4", "vec4"])

var effectLinear = newPostEffect("""
void grad_fill_effect_linear(vec2 startPoint, vec2 diff, vec4 startColor, vec4 endColor) {
    float s = dot(gl_FragCoord.xy-startPoint, diff) / dot(diff, diff);
    vec4 color = mix(startColor, endColor, s);
    color.a *= gl_FragColor.a;
    gl_FragColor = color;
}
""", "grad_fill_effect_linear", ["vec2", "vec2", "vec4", "vec4"])

var effectRadialLocal = newPostEffect("""
void grad_fill_effect_radial_local(vec2 center, float radius, vec4 startColor, vec4 endColor) {
    float dist = distance(center, vPos.xy);
    float d = smoothstep(0.0, 1.0, dist / radius);
    vec4 color = mix(startColor, endColor, d);

    gl_FragColor.rgb = mix(gl_FragColor, color, color.a).rgb;
}
""", "grad_fill_effect_radial_local", ["vec2", "float", "vec4", "vec4"])

var effectRadial = newPostEffect("""
void grad_fill_effect_radial(vec2 center, float radius, vec4 startColor, vec4 endColor) {
    float dist = distance(center, gl_FragCoord.xy);
    float d = dist / radius;
    vec4 color = mix(startColor, endColor, d);
    color.a *= gl_FragColor.a;
    gl_FragColor = color;
}
""", "grad_fill_effect_radial", ["vec2", "float", "vec4", "vec4"])

type RampShape* = enum
    LinearRamp
    RadialRamp

type GradientFill* = ref object of Component
    startPoint*: Point
    endPoint*: Point
    startColor*: Color
    endColor*: Color
    shape*: RampShape
    localCoords*: bool

GradientFill.properties:
    startPoint
    endPoint
    startColor
    endColor
    shape
    localCoords

method serialize*(gf: GradientFill, serealizer: Serializer): JsonNode =
    result = newJObject()
    result.add("startPoint", serealizer.getValue(gf.startPoint))
    result.add("endPoint", serealizer.getValue(gf.endPoint))
    result.add("startColor", serealizer.getValue(gf.startColor))
    result.add("endColor", serealizer.getValue(gf.endColor))
    result.add("shape", serealizer.getValue(gf.shape))

method deserialize*(gf: GradientFill, j: JsonNode, serealizer: Serializer) =
    serealizer.deserializeValue(j, "startPoint", gf.startPoint)
    serealizer.deserializeValue(j, "endPoint", gf.endPoint)
    serealizer.deserializeValue(j, "startColor", gf.startColor)
    serealizer.deserializeValue(j, "endColor", gf.endColor)
    serealizer.deserializeValue(j, "shape", gf.shape)

method beforeDraw*(gf: GradientFill, index: int): bool =
    var tlp: Point
    var brp: Point

    if gf.localCoords:
        tlp = gf.startPoint
        brp = gf.endPoint
    else:
        let tl = gf.startPoint
        let br = gf.endPoint
        let tlv = newVector3(tl.x, tl.y)
        let brv = newVector3(br.x, br.y)

        let sv = gf.node.sceneView

        var screenBounds = sv.bounds
        if not sv.window.isNil:
            screenBounds = sv.window.bounds

        let tlvw = sv.worldToScreenPoint(gf.node.localToWorld(tlv))
        let brvw = sv.worldToScreenPoint(gf.node.localToWorld(brv))

        tlp = sv.convertPointToWindow(newPoint(tlvw.x, tlvw.y))
        brp = sv.convertPointToWindow(newPoint(brvw.x, brvw.y))

        tlp.y = screenBounds.height - tlp.y
        brp.y = screenBounds.height - brp.y

    if gf.shape == RadialRamp:
        let radius = distanceTo(tlp, brp)
        if gf.localCoords:
            pushPostEffect(effectRadialLocal, tlp, radius, gf.startColor, gf.endColor)
        else:
            pushPostEffect(effectRadial, tlp, radius, gf.startColor, gf.endColor)
    else:
        let diff = brp - tlp
        if gf.localCoords:
            pushPostEffect(effectLinearLocal, tlp, brp, gf.startColor, gf.endColor)
        else:
            pushPostEffect(effectLinear, tlp, brp, gf.startColor, gf.endColor)

method afterDraw*(gf: GradientFill, index: int) =
    popPostEffect()

method visitProperties*(gf: GradientFill, p: var PropertyVisitor) =
    p.visitProperty("startPoint", gf.startPoint)
    p.visitProperty("startColor", gf.startColor)
    p.visitProperty("endPoint", gf.endPoint)
    p.visitProperty("endColor", gf.endColor)
    p.visitProperty("shape", gf.shape)
    p.visitProperty("localCoords", gf.localCoords)

genSerializationCodeForComponent(GradientFill)

registerComponent(GradientFill, "Effects")
