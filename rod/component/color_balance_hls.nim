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
import rod / utils / [ property_desc, serialization_codegen ]

type ColorBalanceHLS* = ref object of Component
    hue*: float32
    saturation*: float32
    lightness*: float32
    hlsMin*: float32
    hlsMax*: float32
    enabled: bool

# This effect is borrowed from https://github.com/greggman/hsva-unity  /  HSL version

ColorBalanceHLS.properties:
    hue
    saturation
    lightness
    hlsMin
    hlsMax

var effect = newPostEffect("""
float cbhls_effect_Epsilon = 1e-10;

vec3 cbhls_effect_rgb2hcv(vec3 RGB) {
    // Based on work by Sam Hocevar and Emil Persson
    vec4 P = mix(vec4(RGB.bg, -1.0, 2.0/3.0), vec4(RGB.gb, 0.0, -1.0/3.0), step(RGB.b, RGB.g));
    vec4 Q = mix(vec4(P.xyw, RGB.r), vec4(RGB.r, P.yzx), step(P.x, RGB.r));
    float C = Q.x - min(Q.w, Q.y);
    float H = abs((Q.w - Q.y) / (6.0 * C + cbhls_effect_Epsilon) + Q.z);
    return vec3(H, C, Q.x);
}

vec3 cbhls_effect_rgb2hsl(vec3 RGB) {
    vec3 HCV = cbhls_effect_rgb2hcv(RGB);
    float L = HCV.z - HCV.y * 0.5;
    float S = HCV.y / (1.0 - abs(L * 2.0 - 1.0) + cbhls_effect_Epsilon);
    return vec3(HCV.x, S, L);
}

vec3 cbhls_effect_hsl2rgb(vec3 c) {
    c = vec3(fract(c.x), clamp(c.yz, 0.0, 1.0));
    vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return c.z + c.y * (rgb - 0.5) * (1.0 - abs(2.0 * c.z - 1.0));
}

void cbhls_effect(float hue, float saturation, float lightness, float hlsMin, float hlsMax) {
    vec3 hsl = cbhls_effect_rgb2hsl(gl_FragColor.rgb);
    vec3 adjustment = vec3(hue, saturation, lightness);
    adjustment.xy *= step(0.001, hsl.x + hsl.y);
    float affectMult = step(hlsMin, hsl.r) * step(hsl.r, hlsMax);
    gl_FragColor.rgb = cbhls_effect_hsl2rgb(hsl + adjustment * affectMult);
}
""", "cbhls_effect", ["float", "float", "float", "float", "float"])

method init*(c: ColorBalanceHLS) =
    procCall c.Component.init()
    c.hlsMax = 1.0

# Dirty hack to optimize out extra drawing:
template `~==`(f1, f2: float32): bool = (f1 > f2 - 0.02 and f1 < f2 + 0.02)

template areValuesNormal(c: ColorBalanceHLS): bool =
    c.hue ~== 0 and c.saturation ~== 0 and c.lightness ~== 0

method deserialize*(c: ColorBalanceHLS, j: JsonNode, s: Serializer) =
    c.hue = j["hue"].getFloat()
    c.saturation = j["saturation"].getFloat()
    c.lightness = j["lightness"].getFloat()
    c.hlsMin = j{"hlsMin"}.getFloat()
    c.hlsMax = j{"hlsMax"}.getFloat(1.0)

method serialize*(c: ColorBalanceHLS, s: Serializer): JsonNode =
    result = newJObject()
    result.add("hue", s.getValue(c.hue))
    result.add("saturation", s.getValue(c.saturation))
    result.add("lightness", s.getValue(c.lightness))
    result.add("hlsMin", s.getValue(c.hlsMin))
    result.add("hlsMax", s.getValue(c.hlsMax))

method beforeDraw*(c: ColorBalanceHLS, index: int): bool =
    c.enabled = not c.areValuesNormal()
    if c.enabled:
        pushPostEffect(effect, c.hue, c.saturation, c.lightness, c.hlsMin, c.hlsMax)

method afterDraw*(c: ColorBalanceHLS, index: int) =
    if c.enabled:
        popPostEffect()

method visitProperties*(c: ColorBalanceHLS, p: var PropertyVisitor) =
    p.visitProperty("hue", c.hue)
    p.visitProperty("saturation", c.saturation)
    p.visitProperty("lightness", c.lightness)
    p.visitProperty("hlsMin", c.hlsMin)
    p.visitProperty("hlsMax", c.hlsMax)

genSerializationCodeForComponent(ColorBalanceHLS)
registerComponent(ColorBalanceHLS, "Effects")
