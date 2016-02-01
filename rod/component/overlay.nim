import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.render_to_image
import nimx.matrixes

import rod.node
import rod.viewport

import rod.component

type Overlay* = ref object of OverlayComponent

var overlayComposition = newComposition """
uniform Image uBackground;
uniform Image uForeground;
uniform vec2 viewportSize;

vec2 fbUv(vec4 imgTexCoords) {
    return imgTexCoords.xy + (imgTexCoords.zw - imgTexCoords.xy) * (vPos / viewportSize);
}

void compose() {
    vec2 bgUv = fbUv(uBackground.texCoords);
    vec2 fgUv = fbUv(uForeground.texCoords);
    vec4 burnColor = texture2D(uBackground.tex, bgUv);
    vec4 maskColor = texture2D(uForeground.tex, fgUv);
    gl_FragColor = burnColor * (1.0 + maskColor.a * 2.0);
}
"""

method draw*(o: Overlay) =
    let vp = o.node.sceneView
    let tmpBuf = vp.aquireTempFramebuffer()

    let c = currentContext()
    c.gl.bindFramebuffer(tmpBuf)
    c.gl.clearWithColor(0, 0, 0, 0)
    for c in o.node.children: c.recursiveDraw()

    vp.swapCompositingBuffers()
    let vpbounds = c.gl.getViewport()
    let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

    let o = ortho(vpbounds[0].Coord, vpbounds[2].Coord, vpbounds[3].Coord, vpbounds[1].Coord, -1, 1)

    c.withTransform o:
        overlayComposition.draw newRect(0, 0, vpbounds[2].Coord, vpbounds[3].Coord):
            setUniform("uBackground", vp.mBackupFrameBuffer)
            setUniform("uForeground", tmpBuf)
            setUniform("viewportSize", vpSize)

    vp.releaseTempFramebuffer(tmpBuf)

method isPosteffectComponent*(c: Overlay): bool = true

registerComponent[Overlay]()
