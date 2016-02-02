import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.render_to_image
import json
import rod.node
import rod.viewport

import rod.component
import rod.property_visitor

type ChannelLevels* = ref object of Component
    inWhite*, inBlack*, inGamma*, outWhite*, outBlack*: ColorComponent

var levelsComposition = newComposition """
uniform Image uForeground;
uniform vec2 viewportSize;

uniform float inWhite;
uniform float inBlack;
uniform float inGamma;
uniform float outWhite;
uniform float outBlack;

vec4 colorPow(vec4 i, float p) {
    return vec4(pow(i.r, p), pow(i.g, p), pow(i.b, p), i.a);
}

vec2 fbUv(vec4 imgTexCoords) {
    return imgTexCoords.xy + (imgTexCoords.zw - imgTexCoords.xy) * (vPos / viewportSize);
}

void compose() {
    vec2 uv = fbUv(uForeground.texCoords);
    vec4 inPixel = texture2D(uForeground.tex, uv);
    gl_FragColor = (colorPow(((inPixel) - inBlack) / (inWhite - inBlack),
                    inGamma) * (outWhite - outBlack) + outBlack);
    gl_FragColor.a = inPixel.a;
}
"""

# Dirty hack to optimize out extra drawing:
template `~==`(f1, f2: float): bool = (f1 > f2 - 0.2 and f1 < f2 + 0.2)

template areValuesNormal(c: ChannelLevels): bool =
    c.inWhite ~== 1 and c.inBlack ~== 0 and
        c.inGamma ~== 1 and c.outWhite ~== 1 and c.outBlack ~== 0

method init*(c: ChannelLevels) =
    c.inWhite = 1
    c.inBlack = 0
    c.inGamma = 1
    c.outWhite = 1
    c.outBlack = 0

method deserialize*(c: ChannelLevels, j: JsonNode) =
    c.inWhite = j["inWhite"].getFNum()
    c.inBlack = j["inBlack"].getFNum()
    c.inGamma = j["inGamma"].getFNum()
    c.outWhite = j["outWhite"].getFNum()
    c.outBlack = j["outBlack"].getFNum()

method draw*(cl: ChannelLevels) =
    if not cl.areValuesNormal():
        #echo "GAMMA: ", cl.inWhite, ", ", cl.inBlack, ", ", cl.inGamma, ", ", cl.outWhite, ", ", cl.outBlack
        let vp = cl.node.sceneView
        let c = currentContext()
        let gl = c.gl
        let oldBuf = gl.boundFramebuffer()

        let tmpBuf = vp.aquireTempFramebuffer()

        gl.bindFramebuffer(tmpBuf, false)
        gl.clearWithColor(0, 0, 0, 0)
        for c in cl.node.children: c.recursiveDraw()

        gl.bindFramebuffer(gl.FRAMEBUFFER, oldBuf)

        let vpbounds = gl.getViewport()
        let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

        let o = ortho(vpbounds[0].Coord, vpbounds[2].Coord, vpbounds[3].Coord, vpbounds[1].Coord, -1, 1)

        c.withTransform o:
            levelsComposition.draw newRect(0, 0, vpbounds[2].Coord, vpbounds[3].Coord):
                setUniform("inWhite", cl.inWhite)
                setUniform("inBlack", cl.inBlack)
                setUniform("inGamma", cl.inGamma)
                setUniform("outWhite", cl.outWhite)
                setUniform("outBlack", cl.outBlack)
                setUniform("uForeground", tmpBuf)
                setUniform("viewportSize", vpSize)

        vp.releaseTempFramebuffer(tmpBuf)

method isPosteffectComponent*(c: ChannelLevels): bool = not c.areValuesNormal()

method visitProperties*(c: ChannelLevels, p: var PropertyVisitor) =
    p.visitProperty("inWhite", c.inWhite)
    p.visitProperty("inBlack", c.inBlack)
    p.visitProperty("inGamma", c.inGamma)
    p.visitProperty("outWhite", c.outWhite)
    p.visitProperty("outBlack", c.outBlack)

registerComponent[ChannelLevels]()
