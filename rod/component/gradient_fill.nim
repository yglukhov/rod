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

var effectLinear = newPostEffect("""
void grad_fill_effect(vec2 startPoint, vec2 diff, vec4 startColor, vec4 endColor) {
    float s = dot(gl_FragCoord.xy-startPoint, diff) / dot(diff, diff);
    vec4 color = mix(startColor, endColor, s);
    color.a *= gl_FragColor.a;
    gl_FragColor = color;
}
""", "grad_fill_effect", ["vec2", "vec2", "vec4", "vec4"])

var effectRadial = newPostEffect("""
void grad_fill_effect(vec2 center, float radius, vec4 startColor, vec4 endColor) {
    float dist = distance(center, gl_FragCoord.xy);
    float d = dist / radius;
    vec4 color = mix(startColor, endColor, d);
    color.a *= gl_FragColor.a;
    gl_FragColor = color;
}
""", "grad_fill_effect", ["vec2", "float", "vec4", "vec4"])

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

    var tlp = sv.convertPointToWindow(newPoint(tlvw.x, tlvw.y))
    var brp = sv.convertPointToWindow(newPoint(brvw.x, brvw.y))

    tlp.y = screenBounds.height - tlp.y
    brp.y = screenBounds.height - brp.y

    if gf.shape == RadialRamp:
        let radius = distanceTo(tlp, brp)
        pushPostEffect(effectRadial, tlp, radius, gf.startColor, gf.endColor)
    else:
        let diff = brp - tlp
        pushPostEffect(effectLinear, tlp, diff, gf.startColor, gf.endColor)

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
