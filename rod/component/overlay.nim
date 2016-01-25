import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.render_to_image

import rod.node
import rod.viewport

import rod.component

type Overlay* = ref object of OverlayComponent

var overlayComposition = newComposition """
uniform Image uBackground;
uniform Image uForeground;
uniform vec2 viewportSize;

void compose() {
    vec2 uv = gl_FragCoord.xy / viewportSize * uBackground.texCoords.zw;
    vec4 burnColor = texture2D(uBackground.tex, uv);
    vec4 maskColor = texture2D(uForeground.tex, uv);
    burnColor *= 1.0 + maskColor.a * 2.0;
    gl_FragColor = burnColor;
}
"""

method draw*(o: Overlay) =
    let vp = o.node.sceneView
    let tmpBuf = vp.aquireTempFramebuffer()

    let c = currentContext()
    bindFramebuffer(c.gl, tmpBuf)

    c.gl.clear(c.gl.COLOR_BUFFER_BIT or c.gl.STENCIL_BUFFER_BIT or c.gl.DEPTH_BUFFER_BIT)
    for c in o.node.children: c.recursiveDraw()

    vp.swapCompositingBuffers()
    let vpbounds = c.gl.getViewport()
    let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

    c.withTransform vp.getViewMatrix():
        overlayComposition.draw newRect(0, 0, 1920, 1080):
            setUniform("uBackground", vp.mBackupFrameBuffer)
            setUniform("uForeground", tmpBuf)
            setUniform("viewportSize", vpSize)

    vp.releaseTempFramebuffer(tmpBuf)

method isPosteffectComponent*(c: Overlay): bool = true

registerComponent[Overlay]()
