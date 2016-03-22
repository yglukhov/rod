import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes

import rod.component
import rod.quaternion
import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.camera
import rod.component.sprite
import rod.node
import rod.property_visitor
import rod.viewport

const vertexShader = """
attribute vec4 aPosition;
uniform mat4 mvpMatrix;
void main() { gl_Position = mvpMatrix * vec4(aPosition.xyz, 1.0); }
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform vec4 uColor;
void main() { gl_FragColor = uColor; }
"""
var tracerShader: ProgramRef

const initialIndicesCount = 2000
const initialVerticesCount = 2000

type
    Attrib = enum
        aPosition
    Tracer* = ref object of Component
        color*: Vector4
        indexBuffer: BufferRef
        vertexBuffer: BufferRef
        numberOfIndexes: GLsizei
        vertexOffset: int32
        indexOffset: int32
        prevTransform: Vector3
        traceStep*: int32
        traceStepCounter: int32

proc newTracer(): Tracer =
    new(result, proc(t: Tracer) =
        let c = currentContext()
        let gl = c.gl
        gl.bindBuffer(gl.ARRAY_BUFFER, t.indexBuffer)
        gl.deleteBuffer(t.indexBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
        gl.deleteBuffer(t.vertexBuffer)
        t.indexBuffer = invalidBuffer
        t.vertexBuffer = invalidBuffer
    )

method init*(t: Tracer) =
    procCall t.Component.init()

    t.color = newVector4(0, 0, 0, 1)
    t.numberOfIndexes = 0.GLsizei
    t.traceStep = 5
    t.vertexOffset = 0
    t.traceStepCounter = 0
    t.indexOffset = 0

proc addTraceLine(t: Tracer, point: Vector3) =
    let c = currentContext()
    let gl = c.gl

    var bVertexBufferNeedUpdate, bIndexBufferNeedUpdate: bool

    if (t.vertexOffset + 3*sizeof(GLfloat)) > initialVerticesCount*sizeof(GLfloat):
        bVertexBufferNeedUpdate = true

    if (t.indexOffset + 2*sizeof(GLushort)) > initialIndicesCount*sizeof(GLushort):
        bIndexBufferNeedUpdate = true

    if bIndexBufferNeedUpdate or bVertexBufferNeedUpdate:
        # recreate index_buffer
        gl.bindBuffer(gl.ARRAY_BUFFER, t.indexBuffer)
        gl.deleteBuffer(t.indexBuffer)
        t.indexBuffer = 0
        t.indexOffset = 0
        t.numberOfIndexes = 0.GLsizei

        t.indexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.indexBuffer)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, (initialIndicesCount * sizeof(GLushort)), gl.STREAM_DRAW)

        # recreate array_buffer
        gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
        gl.deleteBuffer(t.vertexBuffer)
        t.vertexBuffer = 0
        t.vertexOffset = 0

        t.vertexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
        gl.bufferData(gl.ARRAY_BUFFER, (initialVerticesCount * sizeof(GLfloat)), gl.STREAM_DRAW)

        # fill buffers with initial data
        var vertexData = @[t.prevTransform[0].GLfloat, t.prevTransform[1], t.prevTransform[2]]
        gl.bufferSubData(gl.ARRAY_BUFFER, t.vertexOffset, vertexData)
        t.vertexOffset += sizeof(GLfloat) * 3

        var indexData = @[(t.numberOfIndexes).GLushort, (t.numberOfIndexes+1).GLushort]
        gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, t.indexOffset, indexData)
        t.indexOffset += sizeof(GLushort) * 2
        t.numberOfIndexes += 1

        bIndexBufferNeedUpdate = false
        bVertexBufferNeedUpdate = false

    if not bIndexBufferNeedUpdate and not bVertexBufferNeedUpdate:
        var vertexData = @[point[0].GLfloat, point[1], point[2]]
        gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
        gl.bufferSubData(gl.ARRAY_BUFFER, t.vertexOffset, vertexData)
        t.vertexOffset += sizeof(GLfloat) * 3

        var indexData = @[(t.numberOfIndexes).GLushort, (t.numberOfIndexes+1).GLushort]
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.indexBuffer)
        gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, t.indexOffset, indexData)
        t.indexOffset += sizeof(GLushort) * 2
        t.numberOfIndexes += 1

proc startTrace(t: Tracer) =
    if t.traceStepCounter == t.traceStep:
        var transform = t.node.worldPos()
        if t.prevTransform != transform:
            t.addTraceLine(transform)
        t.prevTransform = transform
        t.traceStepCounter = 0
    inc t.traceStepCounter

method draw*(t: Tracer) =
    let c = currentContext()
    let gl = c.gl

    if t.indexBuffer == invalidBuffer:
        t.indexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.indexBuffer)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, (initialIndicesCount * sizeof(GLushort)).int32, gl.STREAM_DRAW)
        if t.indexBuffer == invalidBuffer:
            return

    if t.vertexBuffer == invalidBuffer:
        t.vertexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
        gl.bufferData(gl.ARRAY_BUFFER, (initialVerticesCount * sizeof(GLfloat)).int32, gl.STREAM_DRAW)
        if t.vertexBuffer == invalidBuffer:
            return
        else:
            var pos = t.node.worldPos()
            t.addTraceLine(pos)
            t.prevTransform = pos

    if tracerShader == invalidProgram:
        tracerShader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition)])
        if tracerShader == invalidProgram:
            return

    t.startTrace()

    if t.numberOfIndexes > 0:
        gl.enable(gl.DEPTH_TEST)

        gl.enable(gl.DEPTH_TEST)

        gl.bindBuffer(gl.ARRAY_BUFFER, t.vertexBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, t.indexBuffer)
        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (3 * sizeof(GLfloat)).GLsizei , 0)
        gl.useProgram(tracerShader)

        if t.color[3] < 1.0:
            gl.enable(gl.BLEND)
            gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

        gl.uniform4fv(gl.getUniformLocation(tracerShader, "uColor"), t.color)

        let vp = t.node.sceneView
        let mvpMatrix = vp.getViewProjectionMatrix()
        gl.uniformMatrix4fv(gl.getUniformLocation(tracerShader, "mvpMatrix"), false, mvpMatrix)


        gl.drawElements(gl.LINES, t.numberOfIndexes * 2 - 1, gl.UNSIGNED_SHORT)

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

        #TODO to default settings
        gl.disable(gl.DEPTH_TEST)

method visitProperties*(t: Tracer, p: var PropertyVisitor) =
    p.visitProperty("color", t.color)
    p.visitProperty("trace_step", t.traceStep)

# registerComponent[Tracer]()
registerComponent[Tracer](proc(): Component =
    result = newTracer()
    )
