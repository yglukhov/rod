
import math
import tables
import hashes
import sets

import nimx.types
import nimx.portable_gl
import nimx.context

import rod.rod_types

type Shader* = ref object
    vertShader*, fragShader*: string
    program: ProgramRef
    shaderMacroFlags: HashSet[string]
    shadersCache: Table[HashSet[string], tuple[shader: ProgramRef, refCount: int]]
    attributes: seq[tuple[index: GLuint, name: string]]

    needUpdate: bool

# var shadersCache = initTable[HashSet[string], tuple[shader: ProgramRef, refCount: int]]()

proc hash(sm: HashSet[string]): Hash =
    var sum = ""
    for macros in sm:
        sum &= macros
    result = sum.hash()
    result = !$result

proc createShader(sh: Shader) =
    let gl = currentContext().gl
    if not sh.shadersCache.contains(sh.shaderMacroFlags):
        var commonShaderDefines = ""

        var vShader = sh.vertShader
        var fShader = sh.fragShader

        for mcrs in sh.shaderMacroFlags:
            commonShaderDefines &= """#define """ & mcrs & "\n"

            vShader = commonShaderDefines & vShader
            fShader = commonShaderDefines & fShader

        sh.program = gl.newShaderProgram(vShader, fShader, sh.attributes)
        sh.needUpdate = false

        sh.shadersCache[sh.shaderMacroFlags] = (sh.program, 1)

    else:
        sh.program = sh.shadersCache[sh.shaderMacroFlags].shader
        sh.shadersCache[sh.shaderMacroFlags].refCount += 1
        sh.needUpdate = false

proc newShader*(vs, fs: string, attributes: seq[tuple[index: GLuint, name: string]]): Shader =
    result = Shader.new()
    result.vertShader = vs
    result.fragShader = fs
    result.attributes = attributes
    result.needUpdate = true
    result.shaderMacroFlags = initSet[string]()
    result.shadersCache = initTable[HashSet[string], tuple[shader: ProgramRef, refCount: int]]()

    result.createShader()

proc addDefine*(sh: Shader, def: string) =
    sh.shaderMacroFlags.incl(def)
    sh.needUpdate = true

proc removeDefine*(sh: Shader, def: string) =
    sh.shaderMacroFlags.excl(def)
    sh.needUpdate = true

proc bindShader*(sh: Shader) =
    if sh.needUpdate:
        sh.createShader()

    let gl = currentContext().gl
    gl.useProgram(sh.program)

template setUniform*(sh: Shader, name: string, uniform: int) =
    let gl = currentContext().gl
    gl.uniform1i(gl.getUniformLocation(sh.program, name), uniform.GLint)

template setUniform*(sh: Shader, name: string, uniform: float) =
    let gl = currentContext().gl
    gl.uniform1f(gl.getUniformLocation(sh.program, name), uniform)

template setUniform*(sh: Shader, name: string, uniform: Vector2) =
    let gl = currentContext().gl
    gl.uniform2fv(gl.getUniformLocation(sh.program, name), uniform)

template setUniform*(sh: Shader, name: string, uniform: Vector3) =
    let gl = currentContext().gl
    gl.uniform3fv(gl.getUniformLocation(sh.program, name), uniform)

template setUniform*(sh: Shader, name: string, uniform: Vector4) =
    let gl = currentContext().gl
    gl.uniform4fv(gl.getUniformLocation(sh.program, name), uniform)

template setUniform*(sh: Shader, name: string, uniform: Size) =
    currentContext().setPointUniform(gl.getUniformLocation(sh.program, name), newPoint(uniform.width, uniform.height))

template setUniform*(sh: Shader, name: string, uniform: Matrix4) =
    let gl = currentContext().gl
    gl.uniformMatrix4fv(gl.getUniformLocation(sh.program, name), false, uniform)

template setTransformUniform*(sh: Shader) =
    currentContext().setTransformUniform(sh.program)


