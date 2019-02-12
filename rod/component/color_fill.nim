import nimx/[types, context, composition, portable_gl, property_visitor]
import rod/[node, viewport, component, tools.serializer]
import rod / utils / [ property_desc, serialization_codegen ]
import json

type ColorFill* = ref object of Component
    color*: Color

ColorFill.properties:
    color

var effect = newPostEffect("""
void color_fill_effect(vec4 color, float dummy) {
    color.a *= gl_FragColor.a;
    gl_FragColor = color;
}
""", "color_fill_effect", ["vec4", "float"])

method deserialize*(c: ColorFill, j: JsonNode, s: Serializer) =
    var v = j["color"]
    c.color = newColor(v[0].getFloat(), v[1].getFloat(), v[2].getFloat(), v[3].getFloat())

method beforeDraw*(c: ColorFill, index: int): bool =
    const dummyUniform = 0.0'f32 # This unpleasantness is originated from the fact
                                # that new `pushPostEffect` is conflicting with the
                                # old one when number of uniforms is 1.
                                # Should be cleaned up when old `pushPostEffect` is removed
    pushPostEffect(effect, c.color, dummyUniform)

method afterDraw*(c: ColorFill, index: int) =
    popPostEffect()

method visitProperties*(c: ColorFill, p: var PropertyVisitor) =
    p.visitProperty("color", c.color)

genSerializationCodeForComponent(ColorFill)

registerComponent(ColorFill, "Effects")
