import nimx.types
import nimx.context
import nimx.composition
import nimx.portable_gl
import nimx.render_to_image
import nimx.property_visitor

import json

import rod.node
import rod.viewport
import rod.component
import rod.tools.serializer

type ChannelLevels* = ref object of Component
    inWhite*, inBlack*, inGamma*, outWhite*, outBlack*: Coord
    inWhiteV*, inBlackV*, inGammaV*, outWhiteV*, outBlackV*: Vector3
    active: bool

var levelsPostEffect = newPostEffect("""
vec3 colorPow(vec3 i, vec3 p) {
    return vec3(pow(i.r, p.r), pow(i.g, p.g), pow(i.b, p.b));
}

vec3 colorPow(vec3 i, float p) {
    return vec3(pow(i.r, p), pow(i.g, p), pow(i.b, p));
}

void channelLevels(vec3 inWhiteV, vec3 inBlackV, vec3 inGammaV, vec3 outWhiteV,
        vec3 outBlackV, float inWhite, float inBlack, float inGamma, float outWhite, float outBlack) {
    vec3 inPixel = gl_FragColor.rgb;
    inPixel = colorPow((inPixel - inBlackV) / (inWhiteV - inBlackV), inGammaV) * (outWhiteV - outBlackV) + outBlackV;
    inPixel = colorPow((inPixel - inBlack) / (inWhite - inBlack), inGamma) * (outWhite - outBlack) + outBlack;
    gl_FragColor.rgb = inPixel;
}
""", "channelLevels", ["vec3", "vec3", "vec3", "vec3", "vec3", "float", "float", "float", "float", "float"])

# Dirty hack to optimize out extra drawing:
template `~==`(f1, f2: float): bool = (f1 > f2 - 0.2 and f1 < f2 + 0.2)
proc `~==`(v: Vector3, f2: float): bool {.inline.} = v[0] ~== f2 and v[1] ~== f2 and v[2] ~== f2

template areValuesNormal(c: ChannelLevels): bool =
    c.inWhiteV ~== 1 and c.inWhite ~== 1 and
        c.inBlackV ~== 1 and c.inBlack ~== 0 and
        c.inGammaV ~== 1 and c.inGamma ~== 1 and
        c.outWhiteV ~== 1 and c.outWhite ~== 1 and
        c.outBlackV ~== 1 and c.outBlack ~== 0

method init*(c: ChannelLevels) =
    c.inWhiteV = newVector3(1, 1, 1)
    c.inBlackV = newVector3(0, 0, 0)
    c.inGammaV = newVector3(1, 1, 1)
    c.outWhiteV = newVector3(1, 1, 1)
    c.outBlackV = newVector3(0, 0, 0)

    c.inWhite = 1
    c.inBlack = 0
    c.inGamma = 1
    c.outWhite = 1
    c.outBlack = 0

method deserialize*(c: ChannelLevels, j: JsonNode, s: Serializer) =
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

method beforeDraw*(c: ChannelLevels, index: int): bool =
    c.active = not c.areValuesNormal()
    if c.active:
        pushPostEffect(levelsPostEffect, c.inWhiteV, c.inBlackV, c.inGammaV, c.outWhiteV, c.outBlackV, c.inWhite, c.inBlack, c.inGamma, c.outWhite, c.outBlack)

method afterDraw*(c: ChannelLevels, index: int) =
    if c.active:
        popPostEffect()

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

registerComponent(ChannelLevels, "Effects")
