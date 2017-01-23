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

type Tint* = ref object of Component
    black*: Color
    white*: Color
    amount*: float32

var effect = newPostEffect("""
void tint_effect(vec4 black, vec4 white, float amount) {
    float b = (0.2126*gl_FragColor.r + 0.7152*gl_FragColor.g + 0.0722*gl_FragColor.b); // Maybe the koeffs should be adjusted
    float a = gl_FragColor.a;
    vec4 res = mix(black, white, b);
    res.a *= a;
    gl_FragColor = mix(gl_FragColor, res, amount);
}
""", "tint_effect", ["vec4", "vec4", "float"])

method deserialize*(c: Tint, j: JsonNode, s: Serializer) =
    var v = j["black"]
    c.black = newColor(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())
    v = j["white"]
    c.white = newColor(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())
    c.amount = j{"amount"}.getFNum(1)

method beforeDraw*(c: Tint, index: int): bool =
    pushPostEffect(effect, c.black, c.white, c.amount)

method afterDraw*(c: Tint, index: int) =
    popPostEffect()

method isPosteffectComponent*(c: Tint): bool = true

method visitProperties*(c: Tint, p: var PropertyVisitor) =
    p.visitProperty("black", c.black)
    p.visitProperty("white", c.white)
    p.visitProperty("amount", c.amount)

registerComponent(Tint, "Effects")
