import nimx.types
import nimx.context
import nimx.portable_gl
import opengl

import rod.node
import rod.component
import rod.postprocess_context

type BlendMode * = enum
    COLOR_ADD = GL_ONE
    COLOR_SCREEN = GL_ONE_MINUS_SRC_COLOR
    COLOR_MULTIPLY = GL_ONE_MINUS_SRC_ALPHA

type VisualModifier* = ref object of Component
    blendMode*: BlendMode

method init*(vm: VisualModifier) =
    procCall vm.Component.init()
    vm.blendMode = COLOR_ADD

method draw*(vm: VisualModifier) =
    let c = currentContext()
    let gl = c.gl

    if vm.blendMode == COLOR_SCREEN:
        gl.blendFunc(GL_ONE, vm.blendMode.GLenum)
    else:
        gl.blendFunc(gl.SRC_ALPHA, vm.blendMode.GLenum)

    for n in vm.node.children: n.recursiveDraw()

    gl.blendFunc(gl.SRC_ALPHA, COLOR_MULTIPLY.GLenum)

method isPosteffectComponent*(vm: VisualModifier): bool = true

registerComponent[VisualModifier]()
