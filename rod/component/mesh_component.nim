import tables
import hashes
import strutils
import json
import opengl

import nimx.image
import nimx.resource
import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.view
import nimx.system_logger

import nimasset.obj

import rod.component
import rod.component.material
import rod.component.light
import rod.vertex_data_info
import rod.node
import rod.property_visitor
import rod.component.camera
import rod.viewport
import rod.ray
import rod.rod_types

when not defined(ios) and not defined(android) and not defined(js):
    import opengl

import streams

# {.pragma nonserializable.}

type
    VBOData* = ref object
        indexBuffer* : BufferRef
        vertexBuffer*: BufferRef
        numberOfIndices*: GLsizei
        vertInfo*: VertexDataInfo
        minCoord*: Vector3
        maxCoord*: Vector3

    MeshComponent* = ref object of Component
        resourceName*: string
        vboData*: VBOData
        loadFunc: proc()
        material*: Material
        bProccesPostEffects*: bool
        prevTransform*: Matrix4

var vboCache* = initTable[string, VBOData]()

method init*(m: MeshComponent) =
    m.bProccesPostEffects = true
    m.material = newDefaultMaterial()
    m.prevTransform.loadIdentity()
    m.vboData.new()
    m.vboData.minCoord = newVector3(high(int).Coord, high(int).Coord, high(int).Coord)
    m.vboData.maxCoord = newVector3(low(int).Coord, low(int).Coord, low(int).Coord)
    procCall m.Component.init()

proc checkMinMax*(m: MeshComponent, x, y, z: float32) =
    if x < m.vboData.minCoord[0]:
        m.vboData.minCoord[0] = x
    if y < m.vboData.minCoord[1]:
        m.vboData.minCoord[1] = y
    if z < m.vboData.minCoord[2]:
        m.vboData.minCoord[2] = z

    if x > m.vboData.maxCoord[0]:
        m.vboData.maxCoord[0] = x
    if y > m.vboData.maxCoord[1]:
        m.vboData.maxCoord[1] = y
    if z > m.vboData.maxCoord[2]:
        m.vboData.maxCoord[2] = z

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

proc jNodeToColor(j: JsonNode): Color =
    result.r = j[0].getFNum()
    result.g = j[1].getFNum()
    result.b = j[2].getFNum()
    result.a = j[3].getFNum()

method deserialize*(m: MeshComponent, j: JsonNode) =
    if j.isNil:
        return

    proc getValue(name: string, val: var Color) =
        let jN = j{name}
        if not jN.isNil:
            val = jN.jNodeToColor()

    proc getValue(name: string, val: var float32) =
        let jN = j{name}
        if not jN.isNil:
            val = jN.getFnum()

    proc getValue(name: string, val: var bool) =
        let jN = j{name}
        if not jN.isNil:
            val = jN.getBVal()

    proc getValue(name: string, val: var Image) =
        let jN = j{name}
        if not jN.isNil:
            val = imageWithResource(jN.getStr())

    # getValue("emission", m.material.emission)
    # getValue("ambient", m.material.ambient)
    # getValue("diffuse", m.material.diffuse)
    # getValue("specular", m.material.specular)
    # getValue("shininess", m.material.shininess)
    # getValue("reflectivity", m.material.reflectivity)
    # getValue("rim_density", m.material.rim_density)

    # getValue("culling", m.material.bEnableBackfaceCulling)
    # getValue("light", m.material.isLightReceiver)
    # getValue("blend", m.material.blendEnable)
    # getValue("depth_test", m.material.depthEnable)
    # getValue("wireframe", m.material.isWireframe)
    # getValue("RIM", m.material.isRIM)
    # getValue("sRGB_normal", m.material.isNormalSRGB)

    var jNode = j{"emission"}
    m.material.emission = jNode.jNodeToColor()
    jNode = j{"ambient"}
    m.material.ambient = jNode.jNodeToColor()
    jNode = j{"diffuse"}
    m.material.diffuse = jNode.jNodeToColor()
    jNode = j{"specular"}
    m.material.specular = jNode.jNodeToColor()
    jNode = j{"shininess"}
    m.material.shininess = jNode.getFnum()
    jNode = j{"reflectivity"}
    m.material.reflectivity = jNode.getFnum()
    jNode = j{"rim_density"}
    m.material.rim_density = jNode.getFnum()

    jNode = j{"culling"}
    m.material.bEnableBackfaceCulling = jNode.getBVal()
    jNode = j{"light"}
    m.material.isLightReceiver = jNode.getBVal()
    jNode = j{"blend"}
    m.material.blendEnable = jNode.getBVal()
    jNode = j{"depth_test"}
    m.material.depthEnable = jNode.getBVal()
    jNode = j{"wireframe"}
    m.material.isWireframe = jNode.getBVal()
    jNode = j{"RIM"}
    m.material.isRIM = jNode.getBVal()
    jNode = j{"sRGB_normal"}
    m.material.isNormalSRGB = jNode.getBVal()

    proc getTexture(name: string): Image =
        let jNode = j{name}
        if not jNode.isNil:
            result = imageWithResource(jNode.getStr())

    m.material.albedoTexture = getTexture("albedoTexture")
    m.material.glossTexture = getTexture("glossTexture")
    m.material.specularTexture = getTexture("specularTexture")
    m.material.normalTexture = getTexture("normalTexture")
    m.material.bumpTexture = getTexture("bumpTexture")
    m.material.reflectionTexture = getTexture("reflectionTexture")
    m.material.falloffTexture = getTexture("falloffTexture")
    m.material.maskTexture = getTexture("maskTexture")

    proc getAttribs(name: string): seq[float32] =
        result = newSeq[float32]()
        jNode = j{name}
        if not jNode.isNil:
            for v in jNode:
                result.add(v.getFNum())

    var vertCoords = getAttribs("vertex_coords")
    var texCoords = getAttribs("tex_coords")
    var normals = getAttribs("normals")
    var tangents = getAttribs("tangents")

    jNode = j{"indices"}
    var indices = newSeq[GLushort]()
    if not jNode.isNil:
        for v in jNode:
            indices.add( GLushort(v.getNum()) )

    m.vboData.vertInfo = newVertexInfoWithVertexData(vertCoords.len, texCoords.len, normals.len, tangents.len)

    let stride = int32( m.vboData.vertInfo.stride / sizeof(GLfloat) )
    let size = int32(vertCoords.len * stride / 3)
    var vertexData = newSeq[GLfloat](size)
    for i in 0 ..< int32(vertCoords.len / 3):
        var offset = 0
        vertexData[stride * i + 0] = vertCoords[3*i + 0]
        vertexData[stride * i + 1] = vertCoords[3*i + 1]
        vertexData[stride * i + 2] = vertCoords[3*i + 2]
        m.checkMinMax(vertCoords[3*i + 0], vertCoords[3*i + 1], vertCoords[3*i + 2])
        offset += 3

        if texCoords.len != 0:
            vertexData[stride * i + offset + 0] = texCoords[2*i + 0]
            vertexData[stride * i + offset + 1] = texCoords[2*i + 1]
            offset += 2

        if normals.len != 0:
            vertexData[stride * i + offset + 0] = normals[3*i + 0]
            vertexData[stride * i + offset + 1] = normals[3*i + 1]
            vertexData[stride * i + offset + 2] = normals[3*i + 2]
            offset += 3

        if tangents.len != 0:
            vertexData[stride * i + offset + 0] = tangents[3*i + 0]
            vertexData[stride * i + offset + 1] = tangents[3*i + 1]
            vertexData[stride * i + offset + 2] = tangents[3*i + 2]
            offset += 3

    m.createVBO(indices, vertexData)


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

    m.checkMinMax(vertexData[0], vertexData[1], vertexData[2])
    m.checkMinMax(vertexData[0], vertexData[1], vertexData[2])
    m.checkMinMax(vertexData[0], vertexData[1], vertexData[2])
    m.checkMinMax(vertexData[0], vertexData[1], vertexData[2])

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

    if m.vboData.indexBuffer == invalidBuffer:
        m.load()
        if m.vboData.indexBuffer == invalidBuffer:
            return

    gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)

    if not m.bProccesPostEffects or m.node.sceneView.isNil or m.node.sceneView.postprocessContext.isNil or m.node.sceneView.postprocessContext.shader == invalidProgram:
        m.setupAndDraw()
    else:
        m.node.sceneView.postprocessContext.drawProc(m)

    if m.material.bEnableBackfaceCulling:
        gl.disable(gl.CULL_FACE)

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)
    gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(gl.FRONT_AND_BACK, GL_FILL)

    #TODO to default settings
    gl.disable(gl.DEPTH_TEST)
    gl.activeTexture(gl.TEXTURE0)
    gl.enable(gl.BLEND)

proc getIBDataFromVRAM*(c: MeshComponent): seq[GLushort] =
    proc getBufferSubData(target: GLenum, offset: int32, data: var openarray[GLushort]) =
        when defined(js):
            asm "`gl`.BufferSubData(`target`, `offset`, new Uint16Array(`data`));"
        else:
            glGetBufferSubData(target, offset, GLsizei(data.len * sizeof(GLushort)), cast[pointer](data));

    let gl = currentContext().gl

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, c.vboData.indexBuffer)
    let bufSize = gl.getBufferParameteriv(gl.ELEMENT_ARRAY_BUFFER, gl.BUFFER_SIZE)
    let size = int(bufSize / sizeof(GLushort))
    result = newSeq[GLushort](size)

    getBufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, result)

proc getVBDataFromVRAM*(c: MeshComponent): seq[float32] =
    proc getBufferSubData(target: GLenum, offset: int32, data: var openarray[GLfloat]) =
        when defined(js):
            asm "`gl`.BufferSubData(`target`, `offset`, new Float32Array(`data`));"
        else:
            glGetBufferSubData(target, offset, GLsizei(data.len * sizeof(GLfloat)), cast[pointer](data));

    let gl = currentContext().gl

    gl.bindBuffer(gl.ARRAY_BUFFER, c.vboData.vertexBuffer)
    let bufSize = gl.getBufferParameteriv(gl.ARRAY_BUFFER, gl.BUFFER_SIZE)
    let size = int(bufSize / sizeof(float32))
    result = newSeq[float32](size)

    getBufferSubData(gl.ARRAY_BUFFER, 0, result)

proc extractVertexData*(c: MeshComponent, size, offset: int32, data: seq[float32]): seq[float32] =
    let dataStride = int(c.vboData.vertInfo.stride / sizeof(float32))
    let vertCount = int (data.len / dataStride)

    result = newSeq[float32](vertCount * size)
    for i in 0 ..< vertCount:
        for j in 0 ..< size:
            result[ size*i + j ] = data[ dataStride*i + j + offset ]

proc extractVertCoords*(c: MeshComponent, data: seq[float32]): seq[float32] {.procvar.} =
    let size = (int32)c.vboData.vertInfo.numOfCoordPerVert
    let offset = (int32)0
    result = c.extractVertexData(size, offset, data)

proc extractTexCoords*(c: MeshComponent, data: seq[float32]): seq[float32] {.procvar.}  =
    let size = (int32)c.vboData.vertInfo.numOfCoordPerTexCoord
    let offset = (int32)c.vboData.vertInfo.numOfCoordPerVert
    result = c.extractVertexData(size, offset, data)

proc extractNormals*(c: MeshComponent, data: seq[float32]): seq[float32] {.procvar.}  =
    let size = (int32)c.vboData.vertInfo.numOfCoordPerNormal
    let offset = (int32)c.vboData.vertInfo.numOfCoordPerVert + c.vboData.vertInfo.numOfCoordPerTexCoord
    result = c.extractVertexData(size, offset, data)

proc extractTangents*(c: MeshComponent, data: seq[float32]): seq[float32] {.procvar.}  =
    let size = (int32)c.vboData.vertInfo.numOfCoordPerTangent
    let offset = (int32)c.vboData.vertInfo.numOfCoordPerVert + c.vboData.vertInfo.numOfCoordPerTexCoord + c.vboData.vertInfo.numOfCoordPerNormal
    result = c.extractVertexData(size, offset, data)

method rayCast*(c: MeshComponent, r: Ray, distance: var float32): bool =
    var inv_mat: Matrix4
    if tryInverse (c.node.worldTransform(), inv_mat) == false:
        return false

    let localRay = r.transform(inv_mat)
    result = localRay.intersectWithAABB(c.vboData.minCoord, c.vboData.maxCoord, distance)

method visitProperties*(m: MeshComponent, p: var PropertyVisitor) =
    p.visitProperty("emission", m.material.emission)
    p.visitProperty("ambient", m.material.ambient)
    p.visitProperty("diffuse", m.material.diffuse)
    p.visitProperty("specular", m.material.specular)
    p.visitProperty("shininess", m.material.shininess)
    p.visitProperty("reflectivity", m.material.reflectivity)

    p.visitProperty("RIM color", m.material.rimColor)
    p.visitProperty("RIM density", m.material.rimDensity)
    p.visitProperty("RIM enable", m.material.isRIM)

    p.visitProperty("albedoTexture", m.material.albedoTexture)
    p.visitProperty("glossTexture", m.material.glossTexture)
    p.visitProperty("specularTexture", m.material.specularTexture)
    p.visitProperty("normalTexture", m.material.normalTexture)
    p.visitProperty("reflectionTexture", m.material.reflectionTexture)
    p.visitProperty("maskTexture", m.material.maskTexture)
    p.visitProperty("matcapTexture", m.material.matcapTexture)

    p.visitProperty("sRGB normal", m.material.isNormalSRGB)

    p.visitProperty("culling", m.material.bEnableBackfaceCulling)
    p.visitProperty("light", m.material.isLightReceiver)
    p.visitProperty("blend", m.material.blendEnable)
    p.visitProperty("depth test", m.material.depthEnable)
    p.visitProperty("wireframe", m.material.isWireframe)

registerComponent[MeshComponent]()
