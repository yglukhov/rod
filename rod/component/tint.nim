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

var effect = newPostEffect("""
void tint_effect(vec4 black, vec4 white) {
    float b = (0.2126*gl_FragColor.r + 0.7152*gl_FragColor.g + 0.0722*gl_FragColor.b); // Maybe the koeffs should be adjusted
    float a = gl_FragColor.a;
    gl_FragColor = mix(black, white, b);
    gl_FragColor.a *= a;
}
""", "tint_effect", ["vec4", "vec4"])

method deserialize*(c: Tint, j: JsonNode, s: Serializer) =
    var v = j["black"]
    c.black = newColor(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())
    v = j["white"]
    c.white = newColor(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())

method draw*(c: Tint) =
    pushPostEffect(effect, c.black, c.white)
    for c in c.node.children: c.recursiveDraw()
    popPostEffect()

method isPosteffectComponent*(c: Tint): bool = true

method visitProperties*(c: Tint, p: var PropertyVisitor) =
    p.visitProperty("black", c.black)
    p.visitProperty("white", c.white)

registerComponent(Tint, "Effects")
