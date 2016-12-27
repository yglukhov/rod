import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.view
import nimx.property_visitor

import rod.node, rod.viewport, rod.component

import opengl

const clippingRectWithScissors = true

type ClippingRectComponent* = ref object of Component
    clippingRect*: Rect

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

import rod.tools.debug_draw

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

    when clippingRectWithScissors:
        let gl = currentContext().gl
        gl.enable(gl.SCISSOR_TEST)
        let pr = sv.window.pixelRatio
        var x = GLint(tlvw.x * pr)
        var y = GLint((sv.window.bounds.height - brvw.y) * pr)
        var w = GLsizei((brvw.x - tlvw.x) * pr)
        var h = GLSizei((brvw.y - tlvw.y) * pr)
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

method visitProperties*(cl: ClippingRectComponent, p: var PropertyVisitor) =
    p.visitProperty("rect", cl.clippingRect)

registerComponent(ClippingRectComponent)
