import nimx.types
import nimx.context
import nimx.portable_gl
import opengl

import rod.node
import rod.component
import rod.postprocess_context

type BlendMode * = enum
    ONE = GL_ONE
    ONE_MINUS_SRC_ALPHA = GL_ONE_MINUS_SRC_ALPHA

# MULTIPLY
# glBlendFunc(GL_ZERO, GL_SRC_COLOR)

# Multiply = GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA
# Screen = GL_MINUS_DST_COLOR, GL_ONE
# Linear Dodge = GL_ONE, GL_ONE

# Add: GL_ONE, GL_ONE
# Blend: GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA
# Multiply: various, such as the one you mentioned: GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA

type VisualModifier* = ref object of Component
    blendMode*: BlendMode

method init*(vm: VisualModifier) =
    procCall vm.Component.init()

    vm.blendMode = ONE_MINUS_SRC_ALPHA

method draw*(vm: VisualModifier) =
    let c = currentContext()
    let gl = c.gl

    gl.blendFunc(gl.SRC_ALPHA, vm.blendMode.GLenum)

    for n in vm.node.children: n.recursiveDraw()

    gl.blendFunc(gl.SRC_ALPHA, ONE_MINUS_SRC_ALPHA.GLenum)

method isPosteffectComponent*(vm: VisualModifier): bool = true

registerComponent[VisualModifier]()
