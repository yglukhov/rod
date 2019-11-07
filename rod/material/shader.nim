import math, tables, hashes, sets, variant
import nimx/[types, portable_gl, context]
import rod/rod_types


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
    if currentContext().isNil:
        return

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

proc finalize(s: Shader) =
    if s.program != invalidProgram:
        currentContext().gl.deleteProgram(s.program)

proc newShader*(vs, fs: string, attributes: seq[tuple[index: GLuint, name: string]]): Shader =
    result.new(finalize)
    result.vertShader = vs
    result.fragShader = fs
    result.attributes = attributes
    result.needUpdate = true
    result.shaderMacroFlags = initHashSet[string]()
    result.shadersCache = initTable[HashSet[string], tuple[shader: ProgramRef, refCount: int]]()

    result.createShader()

proc bindAttribLocation*(sh: Shader, index: GLuint, name: string) =
    currentContext().gl.bindAttribLocation(sh.program, index, name)

proc addDefine*(sh: Shader, def: string) =
    sh.shaderMacroFlags.incl(def)
    sh.needUpdate = true

proc removeDefine*(sh: Shader, def: string) =
    sh.shaderMacroFlags.excl(def)
    sh.needUpdate = true

proc bindShader*(sh: Shader) =
    if sh.needUpdate:
        sh.createShader()

    if sh.needUpdate == true:
        echo "ERROR! Try to use not created shader program"
        return

    let gl = currentContext().gl
    gl.useProgram(sh.program)

proc setUniform*(sh: Shader, name: string, uniform: int) =
    let gl = currentContext().gl
    gl.uniform1i(gl.getUniformLocation(sh.program, name), uniform.GLint)

proc setUniform*(sh: Shader, name: string, uniform: float) =
    let gl = currentContext().gl
    gl.uniform1f(gl.getUniformLocation(sh.program, name), uniform)

proc setUniform*(sh: Shader, name: string, uniform: Vector2) =
    let gl = currentContext().gl
    gl.uniform2fv(gl.getUniformLocation(sh.program, name), uniform)

proc setUniform*(sh: Shader, name: string, uniform: Vector3) =
    let gl = currentContext().gl
    gl.uniform3fv(gl.getUniformLocation(sh.program, name), uniform)

proc setUniform*(sh: Shader, name: string, uniform: Vector4) =
    let gl = currentContext().gl
    gl.uniform4fv(gl.getUniformLocation(sh.program, name), uniform)

proc setUniform*(sh: Shader, name: string, uniform: Color) =
    let gl = currentContext().gl
    let arr = [uniform.r, uniform.g, uniform.b, uniform.a]
    gl.uniform4fv(gl.getUniformLocation(sh.program, name), arr)

proc setUniform*(sh: Shader, name: string, uniform: Size) =
    let gl = currentContext().gl
    currentContext().setPointUniform(gl.getUniformLocation(sh.program, name), newPoint(uniform.width, uniform.height))

proc setUniform*(sh: Shader, name: string, uniform: Matrix4) =
    let gl = currentContext().gl
    gl.uniformMatrix4fv(gl.getUniformLocation(sh.program, name), false, uniform)

proc setTransformUniform*(sh: Shader) =
    currentContext().setTransformUniform(sh.program)

proc setUniform[T](sh: Shader, name: string, uniform: T) =
    sh.setUniform(name, uniform)


# static uniforms
# this uniforms assign only one time
# but they will setup automatically after bind shader
var procRegistry = initTable[TypeId, proc(sh: Shader, name: string, v: Variant)]()

proc registerProc[T]( setUniformProc: proc(sh: Shader, name: string, value: T) ) =
    procRegistry[getTypeId(T)] = proc(sh: Shader, name: string, v: Variant) =
        let value = v.get(T)
        sh.setUniformProc(name, value)

proc addStaticUniform*[T](sh: Shader, name: string, uniform: T) =
    var u = newVariant(uniform)
    let setter = procRegistry.getOrDefault(u.typeId)
    sh.setter(name, u)

registerProc(setUniform[float])
registerProc(setUniform[int])
registerProc(setUniform[Vector2])
registerProc(setUniform[Vector3])
registerProc(setUniform[Vector4])
registerProc(setUniform[Color])
registerProc(setUniform[Size])
registerProc(setUniform[Matrix4])
