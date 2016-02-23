import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.view

import rod.node
import rod.component

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

proc project(p: Vector3, mat: Matrix4, vp: Size): Point =
    let point3D = mat * p
    result.x = (( point3D.x + 1 ) / 2.0) * vp.width
    result.y = (( 1 - point3D.y ) / 2.0) * vp.height

method draw*(cl: ClippingRectComponent) =
    let c = currentContext()
    let tl = cl.clippingRect.minCorner()
    let br = cl.clippingRect.maxCorner()
    let tlv = newVector3(tl.x, tl.y)
    let brv = newVector3(br.x, br.y)

    let vpbounds = c.gl.getViewport()
    let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

    let tl2 = project(tlv, c.transform, vpSize)
    let br2 = project(brv, c.transform, vpSize)

    when clippingRectWithScissors:
        let gl = c.gl
        gl.enable(gl.SCISSOR_TEST)
        gl.scissor(GLint(tl2.x), GLint(cl.node.sceneView.bounds.height - br2.y), GLsizei(br2.x - tl2.x), GLSizei(br2.y - tl2.y))
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

registerComponent[ClippingRectComponent]()
