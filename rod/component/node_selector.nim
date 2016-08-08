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
import rod.editor.gizmos.move_axis

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
    gizmo: Node
    gizmoAxis: Vector3

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

method init*(ns: NodeSelector) =
    ns.color = newColor(0, 0, 0, 1)
    ns.modelMatrix.loadIdentity()
    procCall ns.Component.init()

proc createBoxes(ns: NodeSelector) =
    for k, v in ns.node.components:
        let bbox = v.getBBox()
        if not bbox.isNil:
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

proc updateGizmo(ns: NodeSelector) =
    var projConstant = 0.005
    ns.gizmo.position = ns.node.worldPos

    var size = (ns.node.sceneView.camera.node.worldPos - ns.node.worldPos).length
    if size < 0.01:
        size = 0.01

    if ns.node.sceneView.camera.projectionMode == cpPerspective:
        ns.gizmo.scale = newVector3(size, size, size) * projConstant
    else:
        size = 10
        ns.gizmo.scale = newVector3(size, size, size)

method componentNodeWasAddedToSceneView*(ns: NodeSelector) =
    ns.createBoxes()

    ns.gizmo = newNode()
    ns.gizmo.loadComposition( getMoveAxisJson() )
    ns.node.mSceneView.rootNode.addChild(ns.gizmo)
    ns.updateGizmo()

method componentNodeWillBeRemovedFromSceneView*(ns: NodeSelector) =
    if not ns.gizmo.isNil:
        ns.gizmo.removeFromParent()

method draw*(ns: NodeSelector) =
    if not ns.vertexData.isNil:
        ns.updateGizmo()

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

        gl.drawElements(gl.LINES, selectorSharedNumberOfIndexes, gl.UNSIGNED_SHORT)

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

        #TODO to default settings
        gl.disable(gl.DEPTH_TEST)

var screenPoint, offset: Vector3
proc startTransform*(ns: NodeSelector, selectedGizmo: Node, position: Point) =
    if selectedGizmo.name.contains("gizmo_axis_x"):
        ns.gizmoAxis = newVector3(1.0, 0.0, 0.0)
    elif selectedGizmo.name.contains("gizmo_axis_y"):
        ns.gizmoAxis = newVector3(0.0, 1.0, 0.0)
    elif selectedGizmo.name.contains("gizmo_axis_z"):
        ns.gizmoAxis = newVector3(0.0, 0.0, 1.0)

    screenPoint = ns.node.sceneView.worldToScreenPoint(ns.gizmo.worldPos)
    offset = ns.gizmo.worldPos - ns.node.sceneView.screenToWorldPoint(newVector3(position.x, position.y, screenPoint.z))

proc proccesTransform*(ns: NodeSelector, position: Point) =
    let scrPoint = ns.node.sceneView.worldToScreenPoint(ns.gizmo.worldPos)
    let worldPoint = ns.node.sceneView.screenToWorldPoint(scrPoint)

    let curScreenPoint = newVector3(position.x, position.y, screenPoint.z)
    var curPosition: Vector3
    curPosition = ns.node.sceneView.screenToWorldPoint(curScreenPoint) + offset
    curPosition = curPosition - ns.gizmo.worldPos
    ns.gizmo.position = ns.gizmo.worldPos + curPosition * ns.gizmoAxis
    ns.node.position = ns.node.parent.worldToLocal(ns.gizmo.position)

proc stopTransform*(ns: NodeSelector) =
    ns.gizmoAxis = newVector3(0.0, 0.0, 0.0)

method visitProperties*(ns: NodeSelector, p: var PropertyVisitor) =
    p.visitProperty("color", ns.color)

registerComponent[NodeSelector]()
