import tables
import strutils

import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.image
import nimx.matrixes
import nimx.property_visitor

import rod.component
import rod.quaternion
import rod.component.mesh_component
import rod.component.material
import rod.component.light
import rod.component.camera
import rod.component.sprite
import rod.node
import rod.viewport
import opengl

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

# let vertexData = [-0.5.GLfloat,-0.5, 0.5,  0.5,-0.5, 0.5,  0.5,0.5, 0.5,  -0.5,0.5, 0.5,
#                   -0.5        ,-0.5,-0.5,  0.5,-0.5,-0.5,  0.5,0.5,-0.5,  -0.5,0.5,-0.5]
let indexData = [0.GLushort, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 3, 7, 2, 6, 0, 4, 1, 5]

var selectorSharedIndexBuffer: BufferRef
var selectorSharedVertexBuffer: BufferRef
var selectorSharedNumberOfIndexes: GLsizei
var selectorSharedShader: ProgramRef

type Attrib = enum
    aPosition

type NodeSelector* = ref object of Component
    modelMatrix*: Matrix4
    vertexData: seq[GLfloat]
    color*: Color

proc trySetupTransformfromNode(ns: NodeSelector, n: Node): bool =
    if not n.isNil:
        let mesh = n.componentIfAvailable(MeshComponent)
        if not mesh.isNil:
            ns.modelMatrix = n.worldTransform()
            # translete selection to bounding box position
            ns.modelMatrix.translate((mesh.vboData.minCoord + mesh.vboData.maxCoord)/2.0)
            ns.modelMatrix.scale(mesh.vboData.maxCoord - mesh.vboData.minCoord)
            return true
        let sprite = n.componentIfAvailable(Sprite)
        if not sprite.isNil and not sprite.image.isNil:
            let w = sprite.image.size.width
            let h = sprite.image.size.height
            ns.modelMatrix = n.worldTransform()
            ns.modelMatrix.translate(newVector3(w/2.0, h/2.0, 0.0) )
            ns.modelMatrix.scale(newVector3(w, h, 0.Coord))
            return true
        let light = n.componentIfAvailable(LightSource)
        if not light.isNil:
            let size = 10.0
            ns.color = light.lightColor
            ns.modelMatrix = n.worldTransform()
            ns.modelMatrix.scale(newVector3(size, size, size))
            return true

proc createVBO(ns: NodeSelector) =
    let c = currentContext()
    let gl = c.gl

    selectorSharedIndexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, selectorSharedIndexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    selectorSharedVertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, selectorSharedVertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, ns.vertexData, gl.STATIC_DRAW)
    selectorSharedNumberOfIndexes = indexData.len.GLsizei

    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)

method init*(ns: NodeSelector) =
    ns.color = newColor(0.12, 1, 0, 1)
    ns.modelMatrix.loadIdentity()
    procCall ns.Component.init()

proc createBoxes(ns: NodeSelector) =
    for k, v in ns.node.components:
        let bbox = v.getBBox()
        if not bbox.isEmpty:
            # echo "node ", ns.node.name, "  min  ", bbox.minPoint, "  max  ", bbox.maxPoint
            ns.vertexData = newSeq[GLfloat]()
            ns.vertexData.add([bbox.minPoint.x, bbox.minPoint.y, bbox.minPoint.z])
            ns.vertexData.add([bbox.maxPoint.x, bbox.minPoint.y, bbox.minPoint.z])
            ns.vertexData.add([bbox.maxPoint.x, bbox.maxPoint.y, bbox.minPoint.z])
            ns.vertexData.add([bbox.minPoint.x, bbox.maxPoint.y, bbox.minPoint.z])

            ns.vertexData.add([bbox.minPoint.x, bbox.minPoint.y, bbox.maxPoint.z])
            ns.vertexData.add([bbox.maxPoint.x, bbox.minPoint.y, bbox.maxPoint.z])
            ns.vertexData.add([bbox.maxPoint.x, bbox.maxPoint.y, bbox.maxPoint.z])
            ns.vertexData.add([bbox.minPoint.x, bbox.maxPoint.y, bbox.maxPoint.z])

            ns.createVBO()


method componentNodeWasAddedToSceneView*(ns: NodeSelector) =
    ns.createBoxes()


method draw*(ns: NodeSelector) =
    if not ns.vertexData.isNil:

        let c = currentContext()
        let gl = c.gl
        ns.modelMatrix = ns.node.worldTransform()

        if selectorSharedShader == invalidProgram:
            selectorSharedShader = gl.newShaderProgram(vertexShader, fragmentShader, [(aPosition.GLuint, $aPosition)])
            if selectorSharedShader == invalidProgram:
                return

        gl.enable(gl.DEPTH_TEST)

        gl.bindBuffer(gl.ARRAY_BUFFER, selectorSharedVertexBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, selectorSharedIndexBuffer)

        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, 3.GLint, gl.FLOAT, false, (3 * sizeof(GLfloat)).GLsizei , 0)

        gl.useProgram(selectorSharedShader)

        c.setColorUniform(selectorSharedShader, "uColor", ns.color)

        let vp = ns.node.sceneView
        let mvpMatrix = vp.getViewProjectionMatrix() * ns.modelMatrix
        gl.uniformMatrix4fv(gl.getUniformLocation(selectorSharedShader, "mvpMatrix"), false, mvpMatrix)

        when not defined(js): glLineWidth(2.0)
        gl.drawElements(gl.LINES, selectorSharedNumberOfIndexes, gl.UNSIGNED_SHORT)
        when not defined(js): glLineWidth(1.0)

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

        #TODO to default settings
        gl.disable(gl.DEPTH_TEST)

method visitProperties*(ns: NodeSelector, p: var PropertyVisitor) =
    p.visitProperty("color", ns.color)

registerComponent(NodeSelector)
