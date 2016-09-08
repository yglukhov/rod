import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.view

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
        let pr = sv.window.pixelRatio
        var x = GLint(tlp.x * pr)
        var y = GLint((sv.window.bounds.height - brp.y) * pr)
        var w = GLsizei((brp.x - tlp.x) * pr)
        var h = GLSizei((brp.y - tlp.y) * pr)

        try:
            gl.scissor(x, y, w, h)
        except:
            discard
        for c in cl.node.children: c.recursiveDraw()
        gl.disable(gl.SCISSOR_TEST)
    else:
        pushPostEffect clippingRectPostEffect:
           setUniform("uTopLeft", tl2)
           setUniform("uBottomRight", br2)
           setUniform("viewportSize", vpSize)

        for c in cl.node.children: c.recursiveDraw()

        popPostEffect()

method isPosteffectComponent*(c: ClippingRectComponent): bool = true

registerComponent(ClippingRectComponent)
