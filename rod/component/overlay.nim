import nimx.types
import nimx.composition
import nimx.portable_gl
import nimx.matrixes

import rod.node
import rod.component

type Overlay* = ref object of Component

var overlayPostEffect = newPostEffect("""

void overlay_effect(float spike, float spike1) {
    vec4 maskColor = gl_FragColor;
    gl_FragColor.rgba = vec4(maskColor.a);
}
""", "overlay_effect", ["float", "float"])

method beforeDraw*(o: Overlay, index: int): bool =
    let c = currentContext()
    c.gl.enable(c.gl.BLEND)
    c.gl.blendFunc(c.gl.DST_COLOR, c.gl.ONE)

    pushPostEffect(overlayPostEffect, 0.0, 0.0)

method afterDraw*(o: Overlay, index: int) =
    let c = currentContext()
    c.gl.blendFunc(c.gl.SRC_ALPHA, c.gl.ONE_MINUS_SRC_ALPHA)
    popPostEffect()

registerComponent(Overlay, "Effects")
