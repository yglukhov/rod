import nimx/[types, composition, portable_gl, matrixes]
import rod / component

type Overlay* = ref object of Component

var overlayPostEffect = newPostEffect("""

void overlay_effect(float spike, float spike1) {
    vec4 maskColor = gl_FragColor;
    gl_FragColor.rgba = vec4(maskColor.a);
}
""", "overlay_effect", ["float", "float"])

method beforeDraw*(o: Overlay, index: int): bool =
    let gl = currentContext().gl
    gl.blendFunc(gl.DST_COLOR, gl.ONE)

    pushPostEffect(overlayPostEffect, 0.0, 0.0)

method afterDraw*(o: Overlay, index: int) =
    let gl = currentContext().gl
    gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
    popPostEffect()

method supportsNewSerialization*(cm: Overlay): bool = true

registerComponent(Overlay, "Effects")
