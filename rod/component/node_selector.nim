import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.matrixes

import rod.component
import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.camera
import rod.node
import rod.property_visitor
import rod.viewport

type Attrib = enum
    aPosition

type NodeSelector* = ref object of Component
    selectedNode: Node

    indexBuffer*: GLuint
    vertexBuffer*: GLuint
    numberOfIndices*: GLsizei
    shader*: ProgramRef

    color*: Vector4

proc trySetupTransformfromNode(ns: NodeSelector, n: Node): bool =
    if not n.isNil:
        let mesh = n.componentIfAvailable(MeshComponent)
        if not mesh.isNil:
            ns.node.translation = n.translation
            ns.node.scale = (mesh.maxCoord - mesh.minCoord) * n.scale
            ns.node.rotation = n.rotation
            result = true

template selectedNode*(ns: NodeSelector): Node = ns.selectedNode
proc `selectedNode=`*(ns: NodeSelector, n: Node) =
    ns.selectedNode = n

const vertexShader = """
attribute vec4 aPosition;
uniform mat4 modelViewProjectionMatrix;
void main() { gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0); }
"""
const fragmentShader = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform vec4 uColor;
void main() { gl_FragColor = uColor; }
"""
proc createVBO(ns: NodeSelector) =
    let c = currentContext()
    let gl = c.gl

    let vertexData = [
        -0.5.GLfloat,-0.5,0.5,
        0.5,-0.5,0.5,
        0.5,0.5,0.5,
        -0.5,0.5,0.5,
        -0.5,-0.5,-0.5,
        0.5,-0.5,-0.5,
        0.5,0.5,-0.5,
        -0.5,0.5,-0.5,
        ]
    let indexData = [0.GLushort, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 3, 7, 2, 6, 0, 4, 1, 5]

    ns.indexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ns.indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    ns.vertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, ns.vertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
    ns.numberOfIndices = indexData.len.GLsizei

proc createShader(ns: NodeSelector) =
    let c = currentContext()
    let gl = c.gl
    ns.shader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition)])

method init*(ns: NodeSelector) =
    ns.color = newVector4(0, 0, 0, 1)
    procCall ns.Component.init()

method draw*(ns: NodeSelector) =
    let c = currentContext()
    let gl = c.gl

    if ns.indexBuffer == 0:
        ns.createVBO()
        if ns.indexBuffer == 0:
            return

    if ns.shader == invalidProgram:
        ns.createShader()
        if ns.shader == invalidProgram:
            return

    if ns.trySetupTransformfromNode(ns.selectedNode):

        gl.enable(gl.DEPTH_TEST)

        gl.bindBuffer(gl.ARRAY_BUFFER, ns.vertexBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ns.indexBuffer)

        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (3 * sizeof(GLfloat)).GLsizei , 0)

        gl.useProgram(ns.shader)

        gl.uniform4fv(gl.getUniformLocation(ns.shader, "uColor"), ns.color)
        c.setTransformUniform(ns.shader)

        gl.drawElements(gl.LINES, ns.numberOfIndices, gl.UNSIGNED_SHORT)

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
