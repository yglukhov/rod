import nimx.image
import nimx.resource
import nimx.context
import nimx.portable_gl
import nimx.types
import nimasset.obj
import strutils

when not defined(ios) and not defined(android) and not defined(js):
    import opengl

import streams

type Attr = enum
    aPosition
    aTexCoord

const vertexShaderDefault* = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;
uniform mat4 modelViewProjectionMatrix;
varying vec2 vTexCoord;
void main()
{
    vTexCoord = aTexCoord;
    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0);
}
"""

const fragmentShaderDefault* = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform sampler2D texUnit;
varying vec2 vTexCoord;
uniform float uAlpha;
uniform float uRed;
uniform vec4 uImageTexCoords;
void main() {
    gl_FragColor = texture2D(texUnit, uImageTexCoords.xy + (uImageTexCoords.zw - uImageTexCoords.xy) * vTexCoord);
    gl_FragColor.a *= uAlpha;
    gl_FragColor.r = max(gl_FragColor.r, uRed);
}
"""

type Mesh* = ref object of RootObj
    texture*: Image
    resourceName: string
    indexBuffer: BufferRef
    vertexBuffer: BufferRef
    numberOfIndices: GLsizei
    loadFunc: proc()
    isWireframe*: bool
    alpha*: GLfloat
    red*: GLfloat
    vertexShader*: string
    fragmentShader*: string
    shader*: ProgramRef

const componentsCount = 5

proc assignShaders*(m: Mesh, vertexShader: string = "", fragmentShader: string = "") =
    m.vertexShader = if vertexShader != "": vertexShader else: vertexShaderDefault
    m.fragmentShader = if fragmentShader != "": fragmentShader else: fragmentShaderDefault

proc mergeIndexes(vertexData, texCoordData: openarray[GLfloat], vertexAttrData: var seq[GLfloat], vi, ti: int): GLushort =
    vertexAttrData.add(vertexData[vi * 3 + 0])
    vertexAttrData.add(vertexData[vi * 3 + 1])
    vertexAttrData.add(vertexData[vi * 3 + 2])
    vertexAttrData.add(texCoordData[ti * 2 + 0])
    vertexAttrData.add(texCoordData[ti * 2 + 1])
    result = GLushort(vertexAttrData.len / 5 - 1)

proc newMeshWithResource*(resourceName: string): Mesh =
    result.new()
    result.alpha = 1.0
    result.assignShaders() # Assign default shaders for mesh
    let m = result
    result.loadFunc = proc() =
        loadResourceAsync resourceName, proc(s: Stream) =
            let loadFunc = proc() =
                var loader: ObjLoader
                var vertexData = newSeq[GLfloat]()
                var texCoordData = newSeq[GLfloat]()
                var vertexAttrData = newSeq[GLfloat]()
                var indexData = newSeq[GLushort]()
                template addVertex(x, y, z: float) =
                    vertexData.add(x)
                    vertexData.add(y)
                    vertexData.add(z)

                template addTexCoord(u, v, w: float) =
                    texCoordData.add(u)
                    texCoordData.add(1.0 - v)

                template uvIndex(t, v: int): int =
                    ## If texture index is not assigned, fallback to vertex index
                    if t == 0: (v - 1) else: (t - 1)

                template addFace(vi0, vi1, vi2, ti0, ti1, ti2, ni0, ni1, ni2: int) =
                    indexData.add(mergeIndexes(vertexData, texCoordData, vertexAttrData, vi0 - 1, uvIndex(ti0, vi0)))
                    indexData.add(mergeIndexes(vertexData, texCoordData, vertexAttrData, vi1 - 1, uvIndex(ti1, vi1)))
                    indexData.add(mergeIndexes(vertexData, texCoordData, vertexAttrData, vi2 - 1, uvIndex(ti2, vi2)))

                loader.loadMeshData(s, addVertex, addTexCoord, addFace)
                s.close()

                let gl = currentContext().gl
                m.indexBuffer = gl.createBuffer()
                gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.indexBuffer)
                gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

                m.vertexBuffer = gl.createBuffer()
                gl.bindBuffer(gl.ARRAY_BUFFER, m.vertexBuffer)
                gl.bufferData(gl.ARRAY_BUFFER, vertexAttrData, gl.STATIC_DRAW)
                m.numberOfIndices = indexData.len.GLsizei
            if currentContext().isNil:
                m.loadFunc = loadFunc
            else:
                loadFunc()

proc newMeshWithQuad*(v1, v2, v3, v4: Vector3, t1, t2, t3, t4: Point): Mesh =
    result.new()
    result.alpha = 1.0
    result.assignShaders() # Assign default shaders for mesh
    let m = result
    result.loadFunc = proc() =
        let gl = currentContext().gl
        let vertexData = [
            v1[0], v1[1], v1[2], t1.x, t1.y,
            v2[0], v2[1], v2[2], t2.x, t2.y,
            v3[0], v3[1], v3[2], t3.x, t3.y,
            v4[0], v4[1], v4[2], t4.x, t4.y
            ]
        let indexData = [0.GLushort, 1, 2, 2, 3, 0]
        m.indexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.indexBuffer)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

        m.vertexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ARRAY_BUFFER, m.vertexBuffer)
        gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
        m.numberOfIndices = indexData.len.GLsizei

proc load(m: Mesh) =
    if not m.loadFunc.isNil:
        m.loadFunc()
        m.loadFunc = nil

proc draw*(m: Mesh) =
    let c = currentContext()
    let gl = c.gl
    if m.shader == invalidProgram:
        m.shader = gl.newShaderProgram(m.vertexShader, m.fragmentShader, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord)])

    if m.indexBuffer == invalidBuffer:
        m.load()
        if m.indexBuffer == invalidBuffer:
            return

    var texCoords : array[4, GLfloat]
    let tex = m.texture.getTextureQuad(gl, texCoords)
    if tex.isEmpty:
        return

    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(GL_FRONT_AND_BACK, if m.isWireframe: GL_LINE else: GL_FILL);

    gl.useProgram(m.shader)
    gl.bindBuffer(gl.ARRAY_BUFFER, m.vertexBuffer)
    gl.enableVertexAttribArray(aPosition.GLuint)
    gl.vertexAttribPointer(aPosition.GLuint, 3, gl.FLOAT, false, 5 * sizeof(GLfloat), 0)
    gl.enableVertexAttribArray(aTexCoord.GLuint)
    gl.vertexAttribPointer(aTexCoord.GLuint, 2, gl.FLOAT, false, 5 * sizeof(GLfloat), 3 * sizeof(GLfloat))

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.indexBuffer)
    c.setTransformUniform(m.shader)
    gl.uniform1f(gl.getUniformLocation(m.shader, "uAlpha"), m.alpha)
    gl.uniform1f(gl.getUniformLocation(m.shader, "uRed"), m.red)

    gl.uniform4fv(gl.getUniformLocation(m.shader, "uImageTexCoords"), texCoords)

    gl.bindTexture(gl.TEXTURE_2D, tex)
    gl.enable(gl.BLEND)
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.drawElements(gl.TRIANGLES, m.numberOfIndices, gl.UNSIGNED_SHORT)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
