import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.property_visitor

import json

import rod.node
import rod.viewport
import rod.component
import rod.tools.serializer

type GradientFill* = ref object of Component
    startPoint*: Point
    endPoint*: Point
    startColor*: Color
    endColor*: Color

var effect = newPostEffect("""
void grad_fill_effect(vec2 startPoint, vec2 endPoint, vec4 startColor, vec4 endColor) {
    vec2 V = endPoint - startPoint;
    float s = dot(vPos.xy-startPoint, V) / dot(V, V); // Vector projection.
    s = clamp(s, 0.0, 1.0); // Saturate scaler.
    vec4 color = mix(startColor, endColor, s); // Gradient color interpolation.
    color.rgb = pow(color.rgb, vec3(1.0/2.2)); // sRGB gamma encode.
    color.a *= gl_FragColor.a;
    gl_FragColor = color;
}
""", "grad_fill_effect", ["vec2", "vec2", "vec4", "vec4"])

method deserialize*(c: GradientFill, j: JsonNode, s: Serializer) =
    var v = j["startPoint"]
    c.startPoint = newPoint(v[0].getFNum(), v[1].getFNum())
    v = j["endPoint"]
    c.endPoint = newPoint(v[0].getFNum(), v[1].getFNum())
    v = j["startColor"]
    c.startColor = newColor(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())
    v = j["endColor"]
    c.endColor = newColor(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())

method draw*(c: GradientFill) =
    pushPostEffect(effect, c.startPoint, c.endPoint, c.startColor, c.endColor)
    for c in c.node.children: c.recursiveDraw()
    popPostEffect()

method isPosteffectComponent*(c: GradientFill): bool = true

method visitProperties*(c: GradientFill, p: var PropertyVisitor) =
    p.visitProperty("startPoint", c.startPoint)
    p.visitProperty("startColor", c.startColor)
    p.visitProperty("endPoint", c.endPoint)
    p.visitProperty("endColor", c.endColor)

registerComponent(GradientFill, "Effects")
