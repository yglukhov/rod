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

type ColorBalanceHLS* = ref object of Component
    hue*: float32
    saturation*: float32
    lightness*: float32
    enabled: bool

var effect = newPostEffect("""
vec3 cbhls_effect_rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 cbhls_effect_hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void cbhls_effect(float hue, float saturation, float lightness) {
    vec3 p = cbhls_effect_rgb2hsv(gl_FragColor.rgb);
    p.x = fract(p.x + hue);
    gl_FragColor.rgb = cbhls_effect_hsv2rgb(p);
}
""", "cbhls_effect", ["float", "float", "float"])

# Dirty hack to optimize out extra drawing:
template `~==`(f1, f2: float32): bool = (f1 > f2 - 0.02 and f1 < f2 + 0.02)

template areValuesNormal(c: ColorBalanceHLS): bool =
    c.hue ~== 0 and c.saturation ~== 0 and c.lightness ~== 0

method deserialize*(c: ColorBalanceHLS, j: JsonNode, s: Serializer) =
    c.hue = j["hue"].getFNum()
    c.saturation = j["saturation"].getFNum()
    c.lightness = j["lightness"].getFNum()

method beforeDraw*(c: ColorBalanceHLS, index: int): bool =
    c.enabled = not c.areValuesNormal()
    if c.enabled:
        pushPostEffect(effect, c.hue, c.saturation, c.lightness)

method afterDraw*(c: ColorBalanceHLS, index: int) =
    if c.enabled:
        popPostEffect()

method visitProperties*(c: ColorBalanceHLS, p: var PropertyVisitor) =
    p.visitProperty("hue", c.hue)
    p.visitProperty("saturation", c.saturation)
    p.visitProperty("lightness", c.lightness)

registerComponent(ColorBalanceHLS, "Effects")
