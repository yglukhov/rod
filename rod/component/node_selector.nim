import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.matrixes

import rod.component
import rod.quaternion
import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.camera
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

let vertexData = [-0.5.GLfloat,-0.5, 0.5,  0.5,-0.5, 0.5,  0.5,0.5, 0.5,  -0.5,0.5, 0.5,
                  -0.5        ,-0.5,-0.5,  0.5,-0.5,-0.5,  0.5,0.5,-0.5,  -0.5,0.5,-0.5]
let indexData = [0.GLushort, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 3, 7, 2, 6, 0, 4, 1, 5]

var indexBuffer: GLuint
var vertexBuffer: GLuint
var numberOfIndices: GLsizei
var shader: ProgramRef

type Attrib = enum
    aPosition

type NodeSelector* = ref object of Component
    modelMatrix*: Matrix4
    color*: Vector4

proc trySetupTransformfromNode(ns: NodeSelector, n: Node): bool =
    if not n.isNil:
        let mesh = n.componentIfAvailable(MeshComponent)
        if not mesh.isNil:
            ns.modelMatrix = n.worldTransform()
            ns.modelMatrix.scale((mesh.vboData.maxCoord - mesh.vboData.minCoord))
            result = true

proc createVBO() =
    let c = currentContext()
    let gl = c.gl

    indexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    vertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
    numberOfIndices = indexData.len.GLsizei

method init*(ns: NodeSelector) =
    ns.color = newVector4(0, 0, 0, 1)
    ns.modelMatrix.loadIdentity()
    procCall ns.Component.init()

method draw*(ns: NodeSelector) =
    let c = currentContext()
    let gl = c.gl

    if indexBuffer == 0:
        createVBO()
        if indexBuffer == 0:
            return

    if shader == invalidProgram:
        shader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition)])
        if shader == invalidProgram:
            return

    if ns.trySetupTransformfromNode(ns.node):
        gl.enable(gl.DEPTH_TEST)

        gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer)

        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (3 * sizeof(GLfloat)).GLsizei , 0)

        gl.useProgram(shader)

        gl.uniform4fv(gl.getUniformLocation(shader, "uColor"), ns.color)

        let vp = ns.node.sceneView
        let mvpMatrix = vp.getViewProjectionMatrix() * ns.modelMatrix
        gl.uniformMatrix4fv(gl.getUniformLocation(shader, "mvpMatrix"), false, mvpMatrix)

        gl.drawElements(gl.LINES, numberOfIndices, gl.UNSIGNED_SHORT)

        when defined(js):
            {.emit: """
            `gl`.bindBuffer(`gl`.ELEMENT_ARRAY_BUFFER, null);
            `gl`.bindBuffer(`gl`.ARRAY_BUFFER, null);
            """.}
        else:
            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
            gl.bindBuffer(gl.ARRAY_BUFFER, 0)

        #TODO to default settings
        gl.disable(gl.DEPTH_TEST)

registerComponent[NodeSelector]()
