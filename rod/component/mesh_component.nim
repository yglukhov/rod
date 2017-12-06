import tables, hashes, strutils, json
import opengl

import nimx / [ image, context, portable_gl, types, view, property_visitor ]
import nimx.assets.url_stream

import nimasset.obj

import rod.component
import rod.component.material
import rod.component.light
import rod.vertex_data_info
import rod.node
import rod.component.camera
import rod.viewport
import rod.ray
import rod.rod_types
import rod.tools.serializer
import rod.utils.bin_deserializer
import rod.utils.image_serialization

import animation.skeleton

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

        skeleton*: Skeleton
        initMesh*: seq[Glfloat]
        currMesh*: seq[Glfloat]
        vertexWeights*: seq[Glfloat]
        boneIDs*: seq[Glfloat]
        boneMap: seq[Bone]

        debugSkeleton*: bool

var vboCache* = initTable[string, VBOData]()

method init*(m: MeshComponent) =
    m.bProccesPostEffects = true
    m.material = newDefaultMaterial()
    m.prevTransform.loadIdentity()
    m.vboData.new()
    m.vboData.minCoord = newVector3(high(int).Coord, high(int).Coord, high(int).Coord)
    m.vboData.maxCoord = newVector3(low(int).Coord, low(int).Coord, low(int).Coord)
    procCall m.Component.init()

    m.debugSkeleton = false

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

        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)

    if currentContext().isNil:
        m.loadFunc = loadFunc
    else:
        loadFunc()

proc loadMeshComponent(m: MeshComponent, resourceName: string) =
    if not vboCache.contains(m.resourceName):
        openStreamForURL("res://" & resourceName) do(s: Stream, err: string):
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

proc prepareBoneMap(m: MeshComponent) =
    m.boneMap = newSeq[Bone]()
    let stride = int(m.vboData.vertInfo.stride / sizeof(Glfloat))
    let vertCount = int(m.currMesh.len / stride)

    for k, v in m.boneIDs:
        let bone = m.skeleton.getBone( m.boneIDs[k].int16 )
        m.boneMap.add(bone)


proc setupAndDraw*(m: MeshComponent) =
    let c = currentContext()
    let gl = c.gl

    m.material.setupVertexAttributes(m.vboData.vertInfo)
    m.material.updateSetup(m.node)
    m.material.setupTransform(m.node)

    if m.material.bEnableBackfaceCulling:
        gl.enable(gl.CULL_FACE)

    if not m.skeleton.isNil:
        if m.boneMap.isNil:
            m.prepareBoneMap()

        m.skeleton.update()

        let stride = int(m.vboData.vertInfo.stride / sizeof(Glfloat))
        let vertCount = int(m.currMesh.len / stride)
        var initPos: Vector3
        for i in 0 ..< vertCount:
            var pos: Vector3
            let currStride = stride * i
            initPos.x = m.initMesh[currStride + 0]
            initPos.y = m.initMesh[currStride + 1]
            initPos.z = m.initMesh[currStride + 2]

            for j in 0 ..< 4:
                let index = 4*i + j
                let vi = m.vertexWeights[index]
                if vi > 0.0:
                    let bone = m.boneMap[index] #m.skeleton.getBone( m.boneIDs[index].int16 )
                    var transformedPos: Vector3
                    bone.matrix.multiply( initPos, transformedPos )
                    pos += transformedPos * m.vertexWeights[index]

            m.currMesh[currStride + 0] = pos.x
            m.currMesh[currStride + 1] = pos.y
            m.currMesh[currStride + 2] = pos.z

        gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
        gl.bufferData(gl.ARRAY_BUFFER, m.currMesh, gl.STATIC_DRAW)

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
        if not m.node.sceneView.isNil and not m.node.sceneView.postprocessContext.isNil:
            m.material.setupShadow(m.node.sceneView.postprocessContext)
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

    if m.debugSkeleton and not m.skeleton.isNil:
        m.skeleton.debugDraw()


method getBBox*(c: MeshComponent): BBox =
    result.maxPoint = c.vboData.maxCoord
    result.minPoint = c.vboData.minCoord

# --------- read data from VBO ------------

proc getIBDataFromVRAM*(c: MeshComponent): seq[GLushort] =
    proc getBufferSubData(target: GLenum, offset: int32, data: var openarray[GLushort]) =
        when defined(android) or defined(ios) or defined(js) or defined(emscripten):
            echo "android and iOS dont't suport glGetBufferSubData"
        else:
            glGetBufferSubData(target, offset, GLsizei(data.len * sizeof(GLushort)), cast[pointer](data));

    let gl = currentContext().gl

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, c.vboData.indexBuffer)
    let bufSize = gl.getBufferParameteriv(gl.ELEMENT_ARRAY_BUFFER, gl.BUFFER_SIZE)
    let size = int(bufSize / sizeof(GLushort))
    result = newSeq[GLushort](size)

    getBufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, result)

proc getVBDataFromVRAM*(c: MeshComponent): seq[float32] =
    if not c.skeleton.isNil:
        return c.initMesh

    proc getBufferSubData(target: GLenum, offset: int32, data: var openarray[GLfloat]) =
        when defined(android) or defined(ios) or defined(js) or defined(emscripten):
            echo "android and iOS dont't suport glGetBufferSubData"
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
    let vertCount = int(data.len / dataStride)

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

method rayCast*(ns: MeshComponent, r: Ray, distance: var float32): bool =
    let distToCam = (ns.node.worldPos - ns.node.sceneView.camera.node.worldPos).length()
    if distToCam < 0.1:
        return false

    result = procCall ns.Component.rayCast(r, distance)

proc createVertexData*(m: MeshComponent, stride, size: int32, vertCoords, texCoords, normals, tangents: seq[float32]): seq[GLfloat] =
    result = newSeq[GLfloat](size)
    for i in 0 ..< int32(vertCoords.len / 3):
        var offset = 0
        result[stride * i + 0] = vertCoords[3*i + 0]
        result[stride * i + 1] = vertCoords[3*i + 1]
        result[stride * i + 2] = vertCoords[3*i + 2]
        m.checkMinMax(vertCoords[3*i + 0], vertCoords[3*i + 1], vertCoords[3*i + 2])
        offset += 3

        if texCoords.len != 0:
            result[stride * i + offset + 0] = texCoords[2*i + 0]
            result[stride * i + offset + 1] = texCoords[2*i + 1]
            offset += 2

        if normals.len != 0:
            result[stride * i + offset + 0] = normals[3*i + 0]
            result[stride * i + offset + 1] = normals[3*i + 1]
            result[stride * i + offset + 2] = normals[3*i + 2]
            offset += 3

        if tangents.len != 0:
            result[stride * i + offset + 0] = tangents[3*i + 0]
            result[stride * i + offset + 1] = tangents[3*i + 1]
            result[stride * i + offset + 2] = tangents[3*i + 2]
            offset += 3

method deserialize*(m: MeshComponent, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "emission", m.material.emission)
    s.deserializeValue(j, "ambient", m.material.ambient)
    s.deserializeValue(j, "diffuse", m.material.diffuse)
    s.deserializeValue(j, "specular", m.material.specular)
    s.deserializeValue(j, "shininess", m.material.shininess)
    s.deserializeValue(j, "rim_density", m.material.rim_density)
    s.deserializeValue(j, "rimColor", m.material.rimColor)

    s.deserializeValue(j, "culling", m.material.bEnableBackfaceCulling)
    s.deserializeValue(j, "light", m.material.isLightReceiver)
    s.deserializeValue(j, "blend", m.material.blendEnable)
    s.deserializeValue(j, "depth_test", m.material.depthEnable)
    s.deserializeValue(j, "wireframe", m.material.isWireframe)
    s.deserializeValue(j, "RIM", m.material.isRIM)
    s.deserializeValue(j, "sRGB_normal", m.material.isNormalSRGB)
    s.deserializeValue(j, "matcapPercentR", m.material.matcapPercentR)
    s.deserializeValue(j, "matcapPercentG", m.material.matcapPercentG)
    s.deserializeValue(j, "matcapPercentB", m.material.matcapPercentB)
    s.deserializeValue(j, "matcapPercentA", m.material.matcapPercentA)
    s.deserializeValue(j, "matcapMaskPercent", m.material.matcapMaskPercent)
    s.deserializeValue(j, "albedoPercent", m.material.albedoPercent)
    s.deserializeValue(j, "glossPercent", m.material.glossPercent)
    s.deserializeValue(j, "specularPercent", m.material.specularPercent)
    s.deserializeValue(j, "normalPercent", m.material.normalPercent)
    s.deserializeValue(j, "bumpPercent", m.material.bumpPercent)
    s.deserializeValue(j, "reflectionPercent", m.material.reflectionPercent)
    s.deserializeValue(j, "falloffPercent", m.material.falloffPercent)
    s.deserializeValue(j, "maskPercent", m.material.maskPercent)

    deserializeImage(j{"matcapTextureR"}, s) do(img: Image, err: string): m.material.matcapTextureR = img
    deserializeImage(j{"matcapTextureG"}, s) do(img: Image, err: string): m.material.matcapTextureG = img
    deserializeImage(j{"matcapTextureB"}, s) do(img: Image, err: string): m.material.matcapTextureB = img
    deserializeImage(j{"matcapTextureA"}, s) do(img: Image, err: string): m.material.matcapTextureA = img
    deserializeImage(j{"matcapMaskTexture"}, s) do(img: Image, err: string): m.material.matcapMaskTexture = img
    deserializeImage(j{"albedoTexture"}, s) do(img: Image, err: string): m.material.albedoTexture = img
    deserializeImage(j{"glossTexture"}, s) do(img: Image, err: string): m.material.glossTexture = img
    deserializeImage(j{"specularTexture"}, s) do(img: Image, err: string): m.material.specularTexture = img
    deserializeImage(j{"normalTexture"}, s) do(img: Image, err: string): m.material.normalTexture = img
    deserializeImage(j{"bumpTexture"}, s) do(img: Image, err: string): m.material.bumpTexture = img
    deserializeImage(j{"reflectionTexture"}, s) do(img: Image, err: string): m.material.reflectionTexture = img
    deserializeImage(j{"falloffTexture"}, s) do(img: Image, err: string): m.material.falloffTexture = img
    deserializeImage(j{"maskTexture"}, s) do(img: Image, err: string): m.material.maskTexture = img

    proc getAttribs(name: string): seq[float32] =
        result = newSeq[float32]()
        let jNode = j{name}
        if not jNode.isNil:
            for v in jNode:
                result.add(v.getFNum())

    var vertCoords = getAttribs("vertex_coords")
    var texCoords = getAttribs("tex_coords")
    var normals = getAttribs("normals")
    var tangents = getAttribs("tangents")

    var jNode = j{"indices"}
    var indices = newSeq[GLushort]()
    if not jNode.isNil:
        for v in jNode:
            indices.add( GLushort(v.getNum()) )

    m.vboData.vertInfo = newVertexInfoWithVertexData(vertCoords.len, texCoords.len, normals.len, tangents.len)

    let stride = int32( m.vboData.vertInfo.stride / sizeof(GLfloat) )
    let size = int32(vertCoords.len * stride / 3)
    var vertexData = m.createVertexData(stride, size, vertCoords, texCoords, normals, tangents)

    m.createVBO(indices, vertexData)

    jNode = j{"skeleton"}
    if not jNode.isNil:
        m.skeleton = newSkeleton()
        m.skeleton.deserialize(jNode, s)

        m.initMesh = vertexData
        m.currMesh = vertexData

        m.vertexWeights = newSeq[Glfloat]()
        m.boneIDs = newSeq[Glfloat]()
        s.deserializeValue(j, "vertexWeights", m.vertexWeights)
        s.deserializeValue(j, "boneIDs", m.boneIDs)

method deserialize*(c: MeshComponent, b: BinDeserializer) =
    c.deserializeFromJson(b)

method serialize*(c: MeshComponent, s: Serializer): JsonNode =
    result = newJObject()

    result.add("emission", s.getValue(c.material.emission))
    result.add("ambient", s.getValue(c.material.ambient))
    result.add("diffuse", s.getValue(c.material.diffuse))
    result.add("specular", s.getValue(c.material.specular))
    result.add("shininess", s.getValue(c.material.shininess))
    result.add("rim_density", s.getValue(c.material.rim_density))

    result.add("culling", s.getValue(c.material.bEnableBackfaceCulling))
    result.add("light", s.getValue(c.material.isLightReceiver))
    result.add("blend", s.getValue(c.material.blendEnable))
    result.add("depth_test", s.getValue(c.material.depthEnable))
    result.add("wireframe", s.getValue(c.material.isWireframe))
    result.add("RIM", s.getValue(c.material.isRIM))
    result.add("rimColor", s.getValue(c.material.rimColor))

    result.add("sRGB_normal", s.getValue(c.material.isNormalSRGB))

    result.add("matcapPercentR", s.getValue(c.material.matcapPercentR))
    result.add("matcapPercentG", s.getValue(c.material.matcapPercentG))
    result.add("matcapPercentB", s.getValue(c.material.matcapPercentB))
    result.add("matcapPercentA", s.getValue(c.material.matcapPercentA))
    result.add("matcapMaskPercent", s.getValue(c.material.matcapMaskPercent))
    result.add("albedoPercent", s.getValue(c.material.albedoPercent))
    result.add("glossPercent", s.getValue(c.material.glossPercent))
    result.add("specularPercent", s.getValue(c.material.specularPercent))
    result.add("normalPercent", s.getValue(c.material.normalPercent))
    result.add("bumpPercent", s.getValue(c.material.bumpPercent))
    result.add("reflectionPercent", s.getValue(c.material.reflectionPercent))
    result.add("falloffPercent", s.getValue(c.material.falloffPercent))
    result.add("maskPercent", s.getValue(c.material.maskPercent))

    if not c.material.matcapTextureR.isNil:
        result.add("matcapTextureR",  s.getValue(s.getRelativeResourcePath(c.material.matcapTextureR.filePath())))
    if not c.material.matcapTextureG.isNil:
        result.add("matcapTextureG",  s.getValue(s.getRelativeResourcePath(c.material.matcapTextureG.filePath())))
    if not c.material.matcapTextureB.isNil:
        result.add("matcapTextureB",  s.getValue(s.getRelativeResourcePath(c.material.matcapTextureB.filePath())))
    if not c.material.matcapTextureA.isNil:
        result.add("matcapTextureA",  s.getValue(s.getRelativeResourcePath(c.material.matcapTextureA.filePath())))
    if not c.material.matcapMaskTexture.isNil:
        result.add("matcapMaskTexture",  s.getValue(s.getRelativeResourcePath(c.material.matcapMaskTexture.filePath())))
    if not c.material.albedoTexture.isNil:
        result.add("albedoTexture",  s.getValue(s.getRelativeResourcePath(c.material.albedoTexture.filePath())))
    if not c.material.glossTexture.isNil:
        result.add("glossTexture",  s.getValue(s.getRelativeResourcePath(c.material.glossTexture.filePath())))
    if not c.material.specularTexture.isNil:
        result.add("specularTexture",  s.getValue(s.getRelativeResourcePath(c.material.specularTexture.filePath())))
    if not c.material.normalTexture.isNil:
        result.add("normalTexture",  s.getValue(s.getRelativeResourcePath(c.material.normalTexture.filePath())))
    if not c.material.bumpTexture.isNil:
        result.add("bumpTexture",  s.getValue(s.getRelativeResourcePath(c.material.bumpTexture.filePath())))
    if not c.material.reflectionTexture.isNil:
        result.add("reflectionTexture",  s.getValue(s.getRelativeResourcePath(c.material.reflectionTexture.filePath())))
    if not c.material.falloffTexture.isNil:
        result.add("falloffTexture",  s.getValue(s.getRelativeResourcePath(c.material.falloffTexture.filePath())))
    if not c.material.maskTexture.isNil:
        result.add("maskTexture",  s.getValue(s.getRelativeResourcePath(c.material.maskTexture.filePath())))

    var data = c.getVBDataFromVRAM()

    proc needsKey(name: string): bool =
        case name
        of "vertex_coords": return c.vboData.vertInfo.numOfCoordPerVert > 0 or false
        of "tex_coords": return c.vboData.vertInfo.numOfCoordPerTexCoord > 0  or false
        of "normals": return c.vboData.vertInfo.numOfCoordPerNormal > 0  or false
        of "tangents": return c.vboData.vertInfo.numOfCoordPerTangent > 0  or false
        else: return false

    template addInfo(name: string, f: typed) =
        if needsKey(name):
            result[name] = s.getValue(f(c, data))

    addInfo("vertex_coords", extractVertCoords)
    addInfo("tex_coords", extractTexCoords)
    addInfo("normals", extractNormals)
    addInfo("tangents", extractTangents)

    var ib = c.getIBDataFromVRAM()
    var ibNode = newJArray()
    result.add("indices", ibNode)
    for v in ib:
        ibNode.add(s.getValue(int32(v)))

    if not c.skeleton.isNil:
        result.add("skeleton", c.skeleton.serialize(s))
        result["vertexWeights"] = s.getValue(c.vertexWeights)
        result["boneIDs"] = s.getValue(c.boneIDs)

method visitProperties*(m: MeshComponent, p: var PropertyVisitor) =
    p.visitProperty("emission", m.material.emission)
    p.visitProperty("ambient", m.material.ambient)
    p.visitProperty("diffuse", m.material.diffuse)
    p.visitProperty("specular", m.material.specular)
    p.visitProperty("shininess", m.material.shininess)

    p.visitProperty("RIM color", m.material.rimColor)
    p.visitProperty("RIM density", m.material.rimDensity)
    p.visitProperty("RIM enable", m.material.isRIM)

    p.visitProperty("albedoTexture", (m.material.albedoTexture, m.material.albedoPercent))
    p.visitProperty("diffuseTexture", (m.material.glossTexture, m.material.glossPercent))
    p.visitProperty("specularTexture", (m.material.specularTexture, m.material.specularPercent))
    p.visitProperty("normalTexture", (m.material.normalTexture, m.material.normalPercent))
    p.visitProperty("reflectionTexture", (m.material.reflectionTexture, m.material.reflectionPercent))
    p.visitProperty("maskTexture", (m.material.maskTexture, m.material.maskPercent))
    p.visitProperty("matcapTextureR", (m.material.matcapTextureR, m.material.matcapPercentR))
    p.visitProperty("matcapTextureG", (m.material.matcapTextureG, m.material.matcapPercentG))
    p.visitProperty("matcapTextureB", (m.material.matcapTextureB, m.material.matcapPercentB))
    p.visitProperty("matcapTextureA", (m.material.matcapTextureA, m.material.matcapPercentA))
    p.visitProperty("matcapMixMask", (m.material.matcapMaskTexture, m.material.matcapMaskPercent))

    p.visitProperty("sRGB normal", m.material.isNormalSRGB)

    p.visitProperty("culling", m.material.bEnableBackfaceCulling)
    p.visitProperty("light", m.material.isLightReceiver)
    p.visitProperty("blend", m.material.blendEnable)
    p.visitProperty("depth test", m.material.depthEnable)
    p.visitProperty("wireframe", m.material.isWireframe)
    p.visitProperty("gammaCorrect", m.material.gammaCorrection)

    if not m.skeleton.isNil:
        p.visitProperty("isPlayed", m.skeleton.isPlayed)
        p.visitProperty("isLooped", m.skeleton.isLooped)
        p.visitProperty("animType", m.skeleton.animType)
        p.visitProperty("debugSkeleton", m.debugSkeleton)

registerComponent(MeshComponent)
