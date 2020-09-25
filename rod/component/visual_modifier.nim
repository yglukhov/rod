import nimx/[types, context, portable_gl]
import rod/[component, tools/serializer]
import rod / utils / [ property_desc, serialization_codegen ]
import opengl, json

type BlendMode * = enum
    COLOR_ADD = GL_ONE
    COLOR_SCREEN = GL_ONE_MINUS_SRC_COLOR
    COLOR_MULTIPLY = GL_ONE_MINUS_SRC_ALPHA

type VisualModifier* = ref object of Component
    blendMode*: BlendMode

VisualModifier.properties:
    discard

method init*(vm: VisualModifier) =
    procCall vm.Component.init()
    vm.blendMode = COLOR_ADD

method beforeDraw*(vm: VisualModifier, index: int): bool =
    let gl = currentContext().gl

    if vm.blendMode == COLOR_SCREEN:
        gl.blendFunc(GL_ONE, vm.blendMode.GLenum)
    else:
        gl.blendFunc(gl.SRC_ALPHA, vm.blendMode.GLenum)

method afterDraw*(vm: VisualModifier, index: int) =
    let gl = currentContext().gl
    gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)

method deserialize*(vm: VisualModifier, j: JsonNode, serealizer: Serializer) =
    var v = j{"blendMode"}
    if not v.isNil:
        let bm = v.getStr()
        case bm
        of "ADD": vm.blendMode = COLOR_ADD
        else: discard

method serialize*(vm: VisualModifier, s: Serializer): JsonNode=
    result = newJObject()
    result.add("blendMode", %($vm.blendMode).substr(5))

genSerializationCodeForComponent(VisualModifier)
registerComponent(VisualModifier, "Effects")
