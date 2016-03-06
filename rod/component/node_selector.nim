import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.matrixes

import rod.component
import rod.component.material
import rod.component.light
import rod.component.camera
import rod.node
import rod.property_visitor
import rod.viewport

type Attrib = enum
    aPosition

type NodeSelector* = ref object of Component
    selectedNodes*: seq[Node]

    indexBuffer*: GLuint
    vertexBuffer*: GLuint
    numberOfIndices*: GLsizei

    currScale*: Vector3


proc createVBO(ns: NodeSelector) =


# method init*(m: MeshComponent) =
#     m.bProccesPostEffects = true
#     m.material = newDefaultMaterial()
#     m.prevTransform.loadIdentity()
#     m.vboData.new()
#     procCall m.Component.init()
# proc createVBO*(m: MeshComponent, indexData: seq[GLushort], vertexAttrData: seq[GLfloat]) =
#     let loadFunc = proc() =
#         let gl = currentContext().gl
#         m.vboData.indexBuffer = gl.createBuffer()
#         gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)
#         gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

#         m.vboData.vertexBuffer = gl.createBuffer()
#         gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
#         gl.bufferData(gl.ARRAY_BUFFER, vertexAttrData, gl.STATIC_DRAW)
#         m.vboData.numberOfIndices = indexData.len.GLsizei

#     if currentContext().isNil:
#         m.loadFunc = loadFunc
#     else:
#         loadFunc()
# method draw*(m: MeshComponent) =
#     let c = currentContext()
#     let gl = c.gl

#     if m.vboData.indexBuffer == 0:
#         m.load()
#         if m.vboData.indexBuffer == 0:
#             return

#     gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
#     gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)

#     template setupAndDraw(m: MeshComponent) =
#         m.material.setupVertexAttributes(m.vboData.vertInfo)
#         m.material.updateSetup(m.node)
#         if m.material.bEnableBackfaceCulling:
#             gl.enable(gl.CULL_FACE)

#         if m.bShowObjectSelection:
#             gl.enable(gl.BLEND)
#             gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
#             gl.uniform1f(gl.getUniformLocation(m.material.shader, "uMaterialTransparency"), 0.5)

#         gl.drawElements(gl.TRIANGLES, m.vboData.numberOfIndices, gl.UNSIGNED_SHORT)

#     if m.node.sceneView.isNil or m.node.sceneView.postprocessContext.isNil or m.node.sceneView.postprocessContext.shader == invalidProgram:
#         m.setupAndDraw()
#     else:
#         let postprocShader = m.node.sceneView.postprocessContext.shader
#         if m.material.shader == invalidProgram or m.material.bShaderNeedUpdate:
#             m.setupAndDraw()
#         let oldShader = m.material.shader

#         let vp = m.node.sceneView
#         let cam = vp.camera
#         var projTransform : Transform3D
#         cam.getProjectionMatrix(vp.bounds, projTransform)

#         let mvpMatrix = projTransform * vp.viewMatrixCached * m.node.worldTransform

#         if postprocShader != invalidProgram:
#             m.material.shader = postprocShader

#         gl.useProgram(m.material.shader)
#         gl.uniformMatrix4fv(gl.getUniformLocation(m.material.shader, "uCurrMVPMatrix"), false, mvpMatrix)
#         gl.uniformMatrix4fv(gl.getUniformLocation(m.material.shader, "uPrevMVPMatrix"), false, m.prevTransform)

#         m.velocityScale = 0.5

#         gl.uniform1f(gl.getUniformLocation(m.material.shader, "uVelocityScale"), m.velocityScale)

#         m.prevTransform = mvpMatrix

#         m.setupAndDraw()
#         m.material.shader = oldShader

#     if m.material.bEnableBackfaceCulling:
#         gl.disable(gl.CULL_FACE)

#     when defined(js):
#         {.emit: """
#         `gl`.bindBuffer(`gl`.ELEMENT_ARRAY_BUFFER, null);
#         `gl`.bindBuffer(`gl`.ARRAY_BUFFER, null);
#         """.}
#     else:
#         gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
#         gl.bindBuffer(gl.ARRAY_BUFFER, 0)
#     when not defined(ios) and not defined(android) and not defined(js):
#         glPolygonMode(gl.FRONT_AND_BACK, GL_FILL)

#     #TODO to default settings
#     gl.disable(gl.DEPTH_TEST)
#     gl.activeTexture(gl.TEXTURE0)
#     gl.enable(gl.BLEND)

registerComponent[NodeSelector]()
