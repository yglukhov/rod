import nimx / [ context, portable_gl, types, matrixes ]
import rod / [ component, node, viewport ]
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

type NodeSelector* = ref object
    mSelectedNode: Node
    vertexData: seq[GLfloat]
    color*: Color

proc createVBO(ns: NodeSelector) =
    let c = currentContext()
    let gl = c.gl

    if selectorSharedIndexBuffer == invalidBuffer:
        selectorSharedIndexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, selectorSharedIndexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    if selectorSharedVertexBuffer == invalidBuffer:
        selectorSharedVertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, selectorSharedVertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, ns.vertexData, gl.STATIC_DRAW)
    selectorSharedNumberOfIndexes = indexData.len.GLsizei

    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)

proc newNodeSelector*(): NodeSelector =
    result.new()
    result.color = newColor(0.12, 1, 0, 1)

proc createBoxes(ns: NodeSelector) =
    for k, v in ns.mSelectedNode.components:
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

proc `selectedNode=`*(ns: NodeSelector, n: Node) =
    ns.mSelectedNode = n
    if not n.isNil:
        ns.createBoxes()

proc draw*(ns: NodeSelector) =
    let node = ns.mSelectedNode
    if not ns.vertexData.isNil and not node.isNil:
        let c = currentContext()
        let gl = c.gl
        let modelMatrix = node.worldTransform()

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

        let vp = node.sceneView
        let mvpMatrix = vp.getViewProjectionMatrix() * modelMatrix
        gl.uniformMatrix4fv(gl.getUniformLocation(selectorSharedShader, "mvpMatrix"), false, mvpMatrix)

        when not defined(js): glLineWidth(2.0)
        gl.drawElements(gl.LINES, selectorSharedNumberOfIndexes, gl.UNSIGNED_SHORT)
        when not defined(js): glLineWidth(1.0)

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)

        #TODO to default settings
        gl.disable(gl.DEPTH_TEST)
