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
    inWhite*, inBlack*, inGamma*, outWhite*, outBlack*: Coord
    inWhiteV*, inBlackV*, inGammaV*, outWhiteV*, outBlackV*: Vector3

var levelsPostEffect = newPostEffect("""
uniform vec3 inWhite;
uniform vec3 inBlack;
uniform vec3 inGamma;
uniform vec3 outWhite;
uniform vec3 outBlack;

vec3 colorPow(vec3 i, vec3 p) {
    return vec3(pow(i.r, p.r), pow(i.g, p.g), pow(i.b, p.b));
}

void channelLevels() {
    vec3 inPixel = gl_FragColor.rgb;
    gl_FragColor.rgb = colorPow((inPixel - inBlack) / (inWhite - inBlack), inGamma) * (outWhite - outBlack) + outBlack;
}
""", "channelLevels")

# Dirty hack to optimize out extra drawing:
template `~==`(f1, f2: float): bool = (f1 > f2 - 0.2 and f1 < f2 + 0.2)
proc `~==`(v: Vector3, f2: float): bool {.inline.} = v[0] ~== f2 and v[1] ~== f2 and v[2] ~== f2

template areValuesNormal(c: ChannelLevels): bool =
    c.inWhiteV * c.inWhite ~== 1 and
        c.inBlackV * c.inBlack ~== 0 and
        c.inGammaV * c.inGamma ~== 1 and
        c.outWhiteV * c.outWhite ~== 1 and
        c.outBlackV * c.outBlack ~== 0

method init*(c: ChannelLevels) =
    c.inWhiteV = newVector3(1, 1, 1)
    c.inBlackV = newVector3(1, 1, 1)
    c.inGammaV = newVector3(1, 1, 1)
    c.outWhiteV = newVector3(1, 1, 1)
    c.outBlackV = newVector3(1, 1, 1)

    c.inWhite = 1
    c.inBlack = 0
    c.inGamma = 1
    c.outWhite = 1
    c.outBlack = 0

method deserialize*(c: ChannelLevels, j: JsonNode) =
    var v = j{"inWhiteV"}
    if not v.isNil:
        c.inWhiteV = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    c.inWhite = j["inWhite"].getFNum()

    v = j{"inBlackV"}
    if not v.isNil:
        c.inBlackV = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    c.inBlack = j["inBlack"].getFNum()

    v = j{"inGammaV"}
    if not v.isNil:
        c.inGammaV = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    c.inGamma = j["inGamma"].getFNum()

    v = j{"outWhiteV"}
    if not v.isNil:
        c.outWhiteV = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    c.outWhite = j["outWhite"].getFNum()

    v = j{"outBlackV"}
    if not v.isNil:
        c.outBlackV = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    c.outBlack = j["outBlack"].getFNum()

method draw*(cl: ChannelLevels) =
    if not cl.areValuesNormal():
        let iw = cl.inWhiteV * cl.inWhite
        let ib = cl.inBlackV * cl.inBlack
        let g = cl.inGammaV * cl.inGamma
        let ow = cl.outWhiteV * cl.outWhite
        let ob = cl.outBlackV * cl.outBlack
        pushPostEffect levelsPostEffect:
            setUniform("inWhite", iw)
            setUniform("inBlack", ib)
            setUniform("inGamma", g)
            setUniform("outWhite", ow)
            setUniform("outBlack", ob)
        for c in cl.node.children: c.recursiveDraw()
        popPostEffect()

method isPosteffectComponent*(c: ChannelLevels): bool = not c.areValuesNormal()

method visitProperties*(c: ChannelLevels, p: var PropertyVisitor) =
    p.visitProperty("inWhiteV", c.inWhiteV)
    p.visitProperty("inBlackV", c.inBlackV)
    p.visitProperty("inGammaV", c.inGammaV)
    p.visitProperty("outWhiteV", c.outWhiteV)
    p.visitProperty("outBlackV", c.outBlackV)

    p.visitProperty("inWhite", c.inWhite)
    p.visitProperty("inBlack", c.inBlack)
    p.visitProperty("inGamma", c.inGamma)
    p.visitProperty("outWhite", c.outWhite)
    p.visitProperty("outBlack", c.outBlack)

    p.visitProperty("redInWhite", c.inWhiteV[0], {pfAnimatable})
    p.visitProperty("greenInWhite", c.inWhiteV[1], {pfAnimatable})
    p.visitProperty("blueInWhite", c.inWhiteV[2], {pfAnimatable})

    p.visitProperty("redInBlack", c.inBlackV[0], {pfAnimatable})
    p.visitProperty("greenInBlack", c.inBlackV[1], {pfAnimatable})
    p.visitProperty("blueInBlack", c.inBlackV[2], {pfAnimatable})

    p.visitProperty("redInGamma", c.inGammaV[0], {pfAnimatable})
    p.visitProperty("greenInGamma", c.inGammaV[1], {pfAnimatable})
    p.visitProperty("blueInGamma", c.inGammaV[2], {pfAnimatable})

    p.visitProperty("redOutWhite", c.outWhiteV[0], {pfAnimatable})
    p.visitProperty("greenOutWhite", c.outWhiteV[1], {pfAnimatable})
    p.visitProperty("blueOutWhite", c.outWhiteV[2], {pfAnimatable})

    p.visitProperty("redOutBlack", c.outBlackV[0], {pfAnimatable})
    p.visitProperty("greenOutBlack", c.outBlackV[1], {pfAnimatable})
    p.visitProperty("blueOutBlack", c.outBlackV[2], {pfAnimatable})

registerComponent[ChannelLevels]()
