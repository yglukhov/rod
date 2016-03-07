import tables
import hashes

import rod.component

import nimx.image
import nimx.resource
import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.view
import nimx.system_logger
import nimasset.obj
import strutils

import rod.component.material
import rod.component.light
import rod.vertex_data_info
import rod.node
import rod.property_visitor
import rod.component.camera
import rod.viewport

when not defined(ios) and not defined(android) and not defined(js):
    import opengl

import streams

type
    VBOData* = ref object
        indexBuffer*: GLuint
        vertexBuffer*: GLuint
        numberOfIndices*: GLsizei
        vertInfo*: VertexDataInfo

    MeshComponent* = ref object of Component
        resourceName*: string
        vboData*: VBOData
        loadFunc: proc()
        material*: Material
        bProccesPostEffects*: bool
        prevTransform*: Matrix4
        minCoord*: Vector3
        maxCoord*: Vector3

var vboCache* = initTable[string, VBOData]()

method init*(m: MeshComponent) =
    m.bProccesPostEffects = true
    m.material = newDefaultMaterial()
    m.prevTransform.loadIdentity()
    m.vboData.new()
    m.minCoord = newVector3(100000000, 100000000, 100000000)
    m.maxCoord = newVector3(-100000000, -100000000, -100000000)
    procCall m.Component.init()

proc checkMinMax*(m: MeshComponent, x, y, z: float32) =

    if x < m.minCoord[0]:
        m.minCoord[0] = x
    if y < m.minCoord[1]:
        m.minCoord[1] = y
    if z < m.minCoord[2]:
        m.minCoord[2] = z

    if x > m.maxCoord[0]:
        m.maxCoord[0] = x
    if y > m.maxCoord[1]:
        m.maxCoord[1] = y
    if z > m.maxCoord[2]:
        m.maxCoord[2] = z

proc mergeIndexes(m: MeshComponent, vertexData, texCoordData, normalData: openarray[GLfloat], vertexAttrData: var seq[GLfloat], vi, ti, ni: int): GLushort =
    var attributesPerVertex: int = 0

    m.checkMinMax(vertexData[vi * 3 + 0], vertexData[vi * 3 + 1], vertexData[vi * 3 + 2])

    vertexAttrData.add(vertexData[vi * 3 + 0])
    vertexAttrData.add(vertexData[vi * 3 + 1])
    vertexAttrData.add(vertexData[vi * 3 + 2])
    attributesPerVertex += 3

    if texCoordData.len > 0 and ti != -1:
        vertexAttrData.add(texCoordData[ti * 2 + 0])
        vertexAttrData.add(texCoordData[ti * 2 + 1])
        attributesPerVertex += 2

    if normalData.len > 0 and ni != -1:
        vertexAttrData.add(normalData[ni * 3 + 0])
        vertexAttrData.add(normalData[ni * 3 + 1])
        vertexAttrData.add(normalData[ni * 3 + 2])
        attributesPerVertex += 3

    result = GLushort(vertexAttrData.len / attributesPerVertex - 1)

proc createVBO*(m: MeshComponent, indexData: seq[GLushort], vertexAttrData: seq[GLfloat]) =
    let loadFunc = proc() =
        let gl = currentContext().gl
        m.vboData.indexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

        m.vboData.vertexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
        gl.bufferData(gl.ARRAY_BUFFER, vertexAttrData, gl.STATIC_DRAW)
        m.vboData.numberOfIndices = indexData.len.GLsizei

    if currentContext().isNil:
        m.loadFunc = loadFunc
    else:
        loadFunc()

proc loadMeshComponent(m: MeshComponent, resourceName: string) =
    if not vboCache.contains(m.resourceName):
        loadResourceAsync resourceName, proc(s: Stream) =
            let loadFunc = proc() =
                var loader: ObjLoader
                var vertexData = newSeq[GLfloat]()
                var texCoordData = newSeq[GLfloat]()
                var normalData = newSeq[GLfloat]()
                var vertexAttrData = newSeq[GLfloat]()
                var indexData = newSeq[GLushort]()
                template addVertex(x, y, z: float) =
                    vertexData.add(x)
                    vertexData.add(y)
                    vertexData.add(z)

                template addNormal(x, y, z: float) =
                    normalData.add(x)
                    normalData.add(y)
                    normalData.add(z)

                template addTexCoord(u, v, w: float) =
                    texCoordData.add(u)
                    texCoordData.add(1.0 - v)

                template uvIndex(t, v: int): int =
                    ## If texture index is not assigned, fallback to vertex index
                    if t == 0: (v - 1) else: (t - 1)

                template addFace(vi0, vi1, vi2, ti0, ti1, ti2, ni0, ni1, ni2: int) =
                    indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi0 - 1, uvIndex(ti0, vi0), ni0 - 1))
                    indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi1 - 1, uvIndex(ti1, vi1), ni1 - 1))
                    indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi2 - 1, uvIndex(ti2, vi2), ni2 - 1))

                loader.loadMeshData(s, addVertex, addTexCoord, addNormal, addFace)
                s.close()

                m.vboData.vertInfo = newVertexInfoWithVertexData(vertexData.len, texCoordData.len, normalData.len)
                m.createVBO(indexData, vertexAttrData)
                vboCache[m.resourceName] = m.vboData

            if currentContext().isNil:
                m.loadFunc = loadFunc
            else:
                loadFunc()
    else:
        m.vboData = vboCache[m.resourceName]

proc loadWithResource*(m: MeshComponent, resourceName: string) =
    m.loadFunc = proc() =
        m.loadMeshComponent(resourceName)

template loadMeshComponentWithResource*(m: MeshComponent, resourceName: string) {.deprecated.} =
    m.loadWithResource(resourceName)

proc loadMeshQuad(m: MeshComponent, v1, v2, v3, v4: Vector3, t1, t2, t3, t4: Point) =
    let gl = currentContext().gl
    let vertexData = [
        v1[0], v1[1], v1[2], t1.x, t1.y,
        v2[0], v2[1], v2[2], t2.x, t2.y,
        v3[0], v3[1], v3[2], t3.x, t3.y,
        v4[0], v4[1], v4[2], t4.x, t4.y
        ]
    let indexData = [0.GLushort, 1, 2, 2, 3, 0]

    m.vboData.vertInfo = newVertexInfoWithVertexData(3, 2)

    m.vboData.indexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    m.vboData.vertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
    m.vboData.numberOfIndices = indexData.len.GLsizei

proc loadWithQuad*(m: MeshComponent, v1, v2, v3, v4: Vector3, t1, t2, t3, t4: Point) =
    m.loadFunc = proc() =
        m.loadMeshQuad(v1, v2, v3, v4, t1, t2, t3, t4)

template meshComponentWithQuad*(m: MeshComponent, v1, v2, v3, v4: Vector3, t1, t2, t3, t4: Point) {.deprecated.} =
    m.loadWithQuad(v1, v2, v3, v4, t1, t2, t3, t4)

proc load(m: MeshComponent) =
    if not m.loadFunc.isNil:
        m.loadFunc()
        m.loadFunc = nil

proc setupAndDraw*(m: MeshComponent) =
    let c = currentContext()
    let gl = c.gl

    m.material.setupVertexAttributes(m.vboData.vertInfo)
    m.material.updateSetup(m.node)
    if m.material.bEnableBackfaceCulling:
        gl.enable(gl.CULL_FACE)

    gl.drawElements(gl.TRIANGLES, m.vboData.numberOfIndices, gl.UNSIGNED_SHORT)

method draw*(m: MeshComponent) =
    let c = currentContext()
    let gl = c.gl

    if m.vboData.indexBuffer == 0:
        m.load()
        if m.vboData.indexBuffer == 0:
            return

    gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)

    if m.node.sceneView.isNil or m.node.sceneView.postprocessContext.isNil or m.node.sceneView.postprocessContext.shader == invalidProgram:
        m.setupAndDraw()
    else:
        m.node.sceneView.postprocessContext.drawProc(m)

    if m.material.bEnableBackfaceCulling:
        gl.disable(gl.CULL_FACE)

    when defined(js):
        {.emit: """
        `gl`.bindBuffer(`gl`.ELEMENT_ARRAY_BUFFER, null);
        `gl`.bindBuffer(`gl`.ARRAY_BUFFER, null);
        """.}
    else:
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
        gl.bindBuffer(gl.ARRAY_BUFFER, 0)
    when not defined(ios) and not defined(android) and not defined(js):
        glPolygonMode(gl.FRONT_AND_BACK, GL_FILL)

    #TODO to default settings
    gl.disable(gl.DEPTH_TEST)
    gl.activeTexture(gl.TEXTURE0)
    gl.enable(gl.BLEND)

method visitProperties*(m: MeshComponent, p: var PropertyVisitor) =
    p.visitProperty("emission", m.material.emission)
    p.visitProperty("ambient", m.material.ambient)
    p.visitProperty("diffuse", m.material.diffuse)
    p.visitProperty("specular", m.material.specular)
    p.visitProperty("shininess", m.material.shininess)
    p.visitProperty("reflectivity", m.material.reflectivity)
    p.visitProperty("rim_density", m.material.rimDensity)

    p.visitProperty("culling", m.material.bEnableBackfaceCulling)
    p.visitProperty("light", m.material.isLightReceiver)
    p.visitProperty("blend", m.material.blendEnable)
    p.visitProperty("depth test", m.material.depthEnable)
    p.visitProperty("wireframe", m.material.isWireframe)
    p.visitProperty("RIM", m.material.isRIM)
    p.visitProperty("sRGB normal", m.material.isNormalSRGB)

registerComponent[MeshComponent]()
