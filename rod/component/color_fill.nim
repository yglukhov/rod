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

type ColorFill* = ref object of Component
    color*: Color

var effect = newPostEffect("""
void color_fill_effect(vec4 color, float dummy) {
    color.a *= gl_FragColor.a;
    gl_FragColor = color;
}
""", "color_fill_effect", ["vec4", "float"])

method deserialize*(c: ColorFill, j: JsonNode, s: Serializer) =
    var v = j["color"]
    c.color = newColor(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())

method draw*(c: ColorFill) =
    const dummyUniform = 0.0'f32 # This unpleasantness is originated from the fact
                                # that new `pushPostEffect` is conflicting with the
                                # old one when number of uniforms is 1.
                                # Should be cleaned up when old `pushPostEffect` is removed
    pushPostEffect(effect, c.color, dummyUniform)
    for c in c.node.children: c.recursiveDraw()
    popPostEffect()

method isPosteffectComponent*(c: ColorFill): bool = true

method visitProperties*(c: ColorFill, p: var PropertyVisitor) =
    p.visitProperty("color", c.color)

registerComponent(ColorFill, "Effects")
