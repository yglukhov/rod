import nimx/[types, context, composition, portable_gl, view, property_visitor]
import rod/[ node, viewport, component, tools/serializer, rod_types]
import rod / utils / [ property_desc, serialization_codegen ]
import json
import opengl


const clippingRectWithScissors = true

type ClippingRectComponent* = ref object of RenderComponent
    clippingRect*: Rect

ClippingRectComponent.properties:
    clippingRect:
        serializationKey: "rect"

when not clippingRectWithScissors:
    var clippingRectPostEffect = newPostEffect("""
    uniform vec2 uTopLeft;
    uniform vec2 uBottomRight;
    uniform vec2 viewportSize;

    float insideBox(vec2 v, vec2 bottomLeft, vec2 topRight) {
        vec2 s = step(bottomLeft, v) - step(topRight, v);
        return s.x * s.y;
    }

    void clipRect() {
        vec2 pos = gl_FragCoord.xy;
        pos.y = viewportSize.y - pos.y;
        gl_FragColor.a *= insideBox(pos, uTopLeft, uBottomRight);
    }
    """, "clipRect")

import rod/tools/debug_draw

proc debugDraw(cl: ClippingRectComponent, rect: Rect) =
    let gl = currentContext().gl
    gl.disable(gl.DEPTH_TEST)
    DDdrawRect(rect, newColor(1.0, 0.2, 0.2, 1.0))
    gl.disable(gl.DEPTH_TEST)

method draw*(cl: ClippingRectComponent) =
    let tl = cl.clippingRect.minCorner()
    let br = cl.clippingRect.maxCorner()
    let tlv = newVector3(tl.x, tl.y)
    let brv = newVector3(br.x, br.y)

    let sv = cl.node.sceneView
    let tlvw = sv.worldToScreenPoint(cl.node.localToWorld(tlv))
    let brvw = sv.worldToScreenPoint(cl.node.localToWorld(brv))

    let tlp = sv.convertPointToWindow(newPoint(tlvw.x, tlvw.y))
    let brp = sv.convertPointToWindow(newPoint(brvw.x, brvw.y))

    when clippingRectWithScissors:
        let gl = currentContext().gl
        gl.enable(gl.SCISSOR_TEST)
        var pr = 1.0'f32
        var b: Rect
        if sv.window.isNil:
            b = sv.bounds
        else:
            pr = sv.window.viewportPixelRatio
            b = sv.window.bounds

        var x = GLint(tlp.x * pr)
        var y = GLint((b.height - brp.y) * pr)
        var w = GLsizei((brp.x - tlp.x) * pr)
        var h = GLSizei((brp.y - tlp.y) * pr)
        if w >= 0 and h >= 0:
            gl.scissor(x, y, w, h)

        for c in cl.node.children: c.recursiveDraw()
        gl.disable(gl.SCISSOR_TEST)

    else:
        pushPostEffect clippingRectPostEffect:
           setUniform("uTopLeft", tl2)
           setUniform("uBottomRight", br2)
           setUniform("viewportSize", vpSize)

        for c in cl.node.children: c.recursiveDraw()

        popPostEffect()

    if cl.node.sceneView.editing:
        cl.debugDraw(cl.clippingRect)

method isPosteffectComponent*(c: ClippingRectComponent): bool = true

method getBBox*(c: ClippingRectComponent): BBox =
    result.minPoint = newVector3(c.clippingRect.x, c.clippingRect.y, 0.0)
    result.maxPoint = newVector3(c.clippingRect.width, c.clippingRect.height, 0.0)

method visitProperties*(cl: ClippingRectComponent, p: var PropertyVisitor) =
    p.visitProperty("rect", cl.clippingRect)

method serialize*(c: ClippingRectComponent, s: Serializer): JsonNode =
    result = newJObject()
    result.add("rect", s.getValue(c.clippingRect))

method deserialize*(c: ClippingRectComponent, j: JsonNode, s: Serializer) =
    s.deserializeValue(j, "rect", c.clippingRect)

genSerializationCodeForComponent(ClippingRectComponent)

registerComponent(ClippingRectComponent)
