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

var overlayPostEffect = newPostEffect("""
uniform Image uBackground;
uniform vec2 viewportSize;

vec2 fbUv(vec4 imgTexCoords) {
    vec2 pos = gl_FragCoord.xy;
    pos.y = viewportSize.y - pos.y;
    return imgTexCoords.xy + (imgTexCoords.zw - imgTexCoords.xy) * (pos / viewportSize);
}

void overlay() {
    vec2 bgUv = fbUv(uBackground.texCoords);
    vec4 burnColor = texture2D(uBackground.tex, bgUv);
    vec4 maskColor = gl_FragColor;
    gl_FragColor.rgb = burnColor.rgb * (1.0 + maskColor.a * 2.0);
}
""", "overlay")

method draw*(o: Overlay) =
    let vp = o.node.sceneView

    vp.swapCompositingBuffers()
    let c = currentContext()

    let bfb = vp.mBackupFrameBuffer

    let vpbounds = c.gl.getViewport()
    let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

    pushPostEffect overlayPostEffect:
        setUniform("uBackground", bfb)
        setUniform("viewportSize", vpSize)

    for c in o.node.children: c.recursiveDraw()

    popPostEffect()

method isPosteffectComponent*(c: Overlay): bool = true

registerComponent[Overlay]()
