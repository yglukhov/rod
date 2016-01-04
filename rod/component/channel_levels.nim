import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.render_to_image
import json
import rod.node
import rod.viewport

import rod.component

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

void compose() {
    vec2 uv = gl_FragCoord.xy / viewportSize * uForeground.texCoords.zw;
    vec4 inPixel = texture2D(uForeground.tex, uv);
    gl_FragColor = (colorPow(((inPixel) - inBlack) / (inWhite - inBlack),
                    inGamma) * (outWhite - outBlack) + outBlack);
    gl_FragColor.a = inPixel.a;
}
"""

template areValuesNormal(c: ChannelLevels): bool =
    c.inWhite == 1 and c.inBlack == 0 and
        c.inGamma == 1 and c.outWhite == 1 and c.outBlack == 0

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
        let oldBuf = cast[GLuint](gl.getParami(gl.FRAMEBUFFER_BINDING))

        let tmpBuf = vp.aquireTempFramebuffer()

        bindFramebuffer(gl, tmpBuf)

        gl.clear(c.gl.COLOR_BUFFER_BIT or c.gl.STENCIL_BUFFER_BIT or c.gl.DEPTH_BUFFER_BIT)
        for c in cl.node.children: c.recursiveDraw()

        gl.bindFramebuffer(gl.FRAMEBUFFER, oldBuf)

        let vpbounds = gl.getViewport()
        let vpSize = newSize(vpbounds[2].Coord, vpbounds[3].Coord)

        c.withTransform vp.getViewMatrix():
            levelsComposition.draw newRect(0, 0, 1920, 1080):
                setUniform("inWhite", cl.inWhite)
                setUniform("inBlack", cl.inBlack)
                setUniform("inGamma", cl.inGamma)
                setUniform("outWhite", cl.outWhite)
                setUniform("outBlack", cl.outBlack)
                setUniform("uForeground", tmpBuf)
                setUniform("viewportSize", vpSize)

        vp.releaseTempFramebuffer(tmpBuf)

method isPosteffectComponent*(c: ChannelLevels): bool = not c.areValuesNormal()
method animatableProperty1*(s: ChannelLevels, name: string): proc (v: Coord) =
    case name
    of "inWhite": result = proc (v: Coord) =
        s.inWhite = v
    of "inBlack": result = proc (v: Coord) =
        s.inBlack = v
    of "inGamma": result = proc (v: Coord) =
        s.inGamma = v
    of "outWhite": result = proc (v: Coord) =
        s.outWhite = v
    of "outBlack": result = proc (v: Coord) =
        s.outBlack = v
    else: result = nil

registerComponent[ChannelLevels]()
