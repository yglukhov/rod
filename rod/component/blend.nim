import json
import opengl
import tables

import nimx.types
import nimx.context
import nimx.matrixes
import nimx.property_visitor
import nimx.portable_gl

import rod.node
import rod.component
import rod.tools.serializer

type BlendFactor * = enum
    ZERO = 0
    ONE
    SRC_COLOR
    ONE_MINUS_SRC_COLOR
    DST_COLOR
    ONE_MINUS_DST_COLOR
    SRC_ALPHA
    ONE_MINUS_SRC_ALPHA
    DST_ALPHA
    ONE_MINUS_DST_ALPHA
    SRC_ALPHA_SATURATE
    CONSTANT_COLOR
    ONE_MINUS_CONSTANT_COLOR
    CONSTANT_ALPHA
    ONE_MINUS_CONSTANT_ALPHA

var blendTable = newTable[BlendFactor, Glenum]()
blendTable[ZERO] = GL_ZERO
blendTable[ONE] = GL_ONE
blendTable[SRC_COLOR] = GL_SRC_COLOR
blendTable[ONE_MINUS_SRC_COLOR] = GL_ONE_MINUS_SRC_COLOR
blendTable[DST_COLOR] = GL_DST_COLOR
blendTable[ONE_MINUS_DST_COLOR] = GL_ONE_MINUS_DST_COLOR
blendTable[SRC_ALPHA] = GL_SRC_ALPHA
blendTable[ONE_MINUS_SRC_ALPHA] = GL_ONE_MINUS_SRC_ALPHA
blendTable[DST_ALPHA] = GL_DST_ALPHA
blendTable[ONE_MINUS_DST_ALPHA] = GL_ONE_MINUS_DST_ALPHA
blendTable[SRC_ALPHA_SATURATE] = GL_SRC_ALPHA_SATURATE
blendTable[CONSTANT_COLOR] = GL_CONSTANT_COLOR
blendTable[ONE_MINUS_CONSTANT_COLOR] = GL_ONE_MINUS_CONSTANT_COLOR
blendTable[CONSTANT_ALPHA] = GL_CONSTANT_ALPHA
blendTable[ONE_MINUS_CONSTANT_ALPHA] = GL_ONE_MINUS_CONSTANT_ALPHA


type Blend* = ref object of Component
    source*: BlendFactor
    destination*: BlendFactor
    enabled: bool
    # equation*:

method init*(b: Blend) =
    b.enabled = true
    b.source = BlendFactor.ONE_MINUS_SRC_COLOR
    b.destination = BlendFactor.ONE_MINUS_SRC_ALPHA

method deserialize*(b: Blend, j: JsonNode, serializer: Serializer) =
    serializer.deserializeValue(j, "source", b.source)
    serializer.deserializeValue(j, "destination", b.destination)

method draw*(b: Blend) =
    let c = currentContext()
    let gl = c.gl
    if b.enabled:
        gl.enable(GL_BLEND)
    else:
        gl.disable(GL_BLEND)

    gl.blendFunc(blendTable[b.source], blendTable[b.destination])

method visitProperties*(c: Blend, p: var PropertyVisitor) =
    p.visitProperty("enabled", c.enabled)
    p.visitProperty("source", c.source)
    p.visitProperty("destination", c.destination)

method serialize*(c: Blend, s: Serializer): JsonNode =
    result = newJObject()
    result.add("enabled", s.getValue(c.enabled))
    result.add("source", s.getValue(c.source))
    result.add("destination", s.getValue(c.destination))

registerComponent(Blend, "Graphics")
