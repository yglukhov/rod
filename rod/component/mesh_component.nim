import nimx / [ image, context, portable_gl, types, view, property_visitor, assets/url_stream ]
import rod/[component, vertex_data_info, node, ray, rod_types]
import rod/component/[material]
import rod/utils/[property_desc, serialization_codegen]
import animation/skeleton
import tables, hashes, strutils, streams
import opengl
import nimasset/obj

type
    VBOData* = ref object
        indexBuffer* : BufferRef
        vertexBuffer*: BufferRef
        numberOfIndices*: GLsizei
        vertInfo*: VertexDataInfo
        minCoord*: Vector3
        maxCoord*: Vector3
        indexData*: seq[GLushort]
        vertexAttrData*: seq[GLfloat]

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

MeshComponent.properties:
    emission(phantom = Color, default = invalidShaderColor())
    ambient(phantom = Color, default = invalidShaderColor())
    diffuse(phantom = Color, default = invalidShaderColor())
    specular(phantom = Color, default = invalidShaderColor())
    shininess(phantom = Coord, default = invalidShaderValue)
    rimDensity(phantom = Coord)
    rimColor(phantom = Color)

    culling(phantom = bool, default = true)
    light(phantom = bool, default = true)
    blend(phantom = bool)
    depth_test(phantom = bool, default = true)
    wireframe(phantom = bool)
    isRIM:
        phantom: bool
        serializationKey: "RIM"
    sRGB_normal(phantom = bool)
    matcapPercentR(phantom = float32, default = 1.0)
    matcapPercentG(phantom = float32, default = 1.0)
    matcapPercentB(phantom = float32, default = 1.0)
    matcapPercentA(phantom = float32, default = 1.0)
    matcapMaskPercent(phantom = float32, default = 1.0)
    albedoPercent(phantom = float32, default = 1.0)
    glossPercent(phantom = float32, default = 1.0)
    specularPercent(phantom = float32, default = 1.0)
    normalPercent(phantom = float32, default = 1.0)
    bumpPercent(phantom = float32, default = 1.0)
    reflectionPercent(phantom = float32, default = 1.0)
    falloffPercent(phantom = float32, default = 1.0)
    maskPercent(phantom = float32, default = 1.0)

    matcapTextureR(phantom = Image)
    matcapTextureG(phantom = Image)
    matcapTextureB(phantom = Image)
    matcapTextureA(phantom = Image)
    matcapMaskTexture(phantom = Image)
    albedoTexture(phantom = Image)
    glossTexture(phantom = Image)
    specularTexture(phantom = Image)
    normalTexture(phantom = Image)
    bumpTexture(phantom = Image)
    reflectionTexture(phantom = Image)
    falloffTexture(phantom = Image)
    maskTexture(phantom = Image)

    vertex_coords(phantom = seq[float32])
    tex_coords(phantom = seq[float32])
    normals(phantom = seq[float32])
    tangents(phantom = seq[float32])

    indices(phantom = seq[uint16])

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
    m.vboData.indexData = indexData
    m.vboData.vertexAttrData = vertexAttrData

    let loadFunc = proc() =
        assert(m.vboData.vertexAttrData.len != 0)
        let gl = currentContext().gl
        m.vboData.indexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexBuffer)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, m.vboData.indexData, gl.STATIC_DRAW)

        m.vboData.vertexBuffer = gl.createBuffer()
        gl.bindBuffer(gl.ARRAY_BUFFER, m.vboData.vertexBuffer)
        gl.bufferData(gl.ARRAY_BUFFER, m.vboData.vertexAttrData, gl.STATIC_DRAW)
        m.vboData.numberOfIndices = m.vboData.indexData.len.GLsizei

        gl.bindBuffer(gl.ARRAY_BUFFER, invalidBuffer)
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, invalidBuffer)

        m.vboData.indexData = @[]
        m.vboData.vertexAttrData = @[]

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
        if m.boneMap.len == 0:
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

proc getIBData*(c: MeshComponent): seq[GLushort] =
    proc getBufferSubData(target: GLenum, offset: int32, data: var openarray[GLushort]) =
        when defined(android) or defined(ios) or defined(js) or defined(emscripten):
            echo "android and iOS dont't suport glGetBufferSubData"
        else:
            glGetBufferSubData(target, offset, GLsizei(data.len * sizeof(GLushort)), cast[pointer](data));

    if c.vboData.indexData.len == 0:
        let gl = currentContext().gl

        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, c.vboData.indexBuffer)
        let bufSize = gl.getBufferParameteriv(gl.ELEMENT_ARRAY_BUFFER, gl.BUFFER_SIZE)
        let size = int(bufSize / sizeof(GLushort))
        result = newSeq[GLushort](size)

        getBufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, result)
    else:
        return c.vboData.indexData

proc getVBData*(c: MeshComponent): seq[float32] =
    if not c.skeleton.isNil:
        return c.initMesh

    proc getBufferSubData(target: GLenum, offset: int32, data: var openarray[GLfloat]) =
        when defined(android) or defined(ios) or defined(js) or defined(emscripten):
            echo "android and iOS dont't suport glGetBufferSubData"
        else:
            glGetBufferSubData(target, offset, GLsizei(data.len * sizeof(GLfloat)), cast[pointer](data));

    if c.vboData.vertexAttrData.len == 0:
        let gl = currentContext().gl

        gl.bindBuffer(gl.ARRAY_BUFFER, c.vboData.vertexBuffer)
        let bufSize = gl.getBufferParameteriv(gl.ARRAY_BUFFER, gl.BUFFER_SIZE)
        let size = int(bufSize / sizeof(float32))
        result = newSeq[float32](size)

        getBufferSubData(gl.ARRAY_BUFFER, 0, result)
    else:
        return c.vboData.vertexAttrData

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

proc toPhantom(c: MeshComponent, p: var object) =
    p.emission = c.material.emission
    p.ambient = c.material.ambient
    p.diffuse = c.material.diffuse
    p.specular = c.material.specular
    p.shininess = c.material.shininess
    p.rim_density = c.material.rim_density

    p.culling = c.material.bEnableBackfaceCulling
    p.light = c.material.isLightReceiver
    p.blend = c.material.blendEnable
    p.depth_test = c.material.depthEnable
    p.wireframe = c.material.isWireframe
    p.isRIM = c.material.isRIM
    p.rimColor = c.material.rimColor

    p.sRGB_normal = c.material.isNormalSRGB

    p.matcapPercentR = c.material.matcapPercentR
    p.matcapPercentG = c.material.matcapPercentG
    p.matcapPercentB = c.material.matcapPercentB
    p.matcapPercentA = c.material.matcapPercentA
    p.matcapMaskPercent = c.material.matcapMaskPercent
    p.albedoPercent = c.material.albedoPercent
    p.glossPercent = c.material.glossPercent
    p.specularPercent = c.material.specularPercent
    p.normalPercent = c.material.normalPercent
    p.bumpPercent = c.material.bumpPercent
    p.reflectionPercent = c.material.reflectionPercent
    p.falloffPercent = c.material.falloffPercent
    p.maskPercent = c.material.maskPercent

    p.matcapTextureR = c.material.matcapTextureR
    p.matcapTextureG = c.material.matcapTextureG
    p.matcapTextureB = c.material.matcapTextureB
    p.matcapTextureA = c.material.matcapTextureA
    p.matcapMaskTexture = c.material.matcapMaskTexture
    p.albedoTexture = c.material.albedoTexture
    p.glossTexture = c.material.glossTexture
    p.specularTexture = c.material.specularTexture
    p.normalTexture = c.material.normalTexture
    p.bumpTexture = c.material.bumpTexture
    p.reflectionTexture = c.material.reflectionTexture
    p.falloffTexture = c.material.falloffTexture
    p.maskTexture = c.material.maskTexture

    let data = c.getVBData()

    if c.vboData.vertInfo.numOfCoordPerVert > 0:
        p.vertex_coords = c.extractVertCoords(data)

    if c.vboData.vertInfo.numOfCoordPerTexCoord > 0:
        p.tex_coords = c.extractTexCoords(data)

    if c.vboData.vertInfo.numOfCoordPerNormal > 0:
        p.normals = c.extractNormals(data)

    if c.vboData.vertInfo.numOfCoordPerTangent > 0:
        p.tangents = c.extractTangents(data)

    p.indices = c.getIBData()
    # TODO: Save skeleton

proc fromPhantom(c: MeshComponent, p: object) =
    c.material.emission = p.emission
    c.material.ambient = p.ambient
    c.material.diffuse = p.diffuse
    c.material.specular = p.specular
    c.material.shininess = p.shininess
    c.material.rim_density = p.rim_density

    c.material.bEnableBackfaceCulling = p.culling
    c.material.isLightReceiver = p.light
    c.material.blendEnable = p.blend
    c.material.depthEnable = p.depth_test
    c.material.isWireframe = p.wireframe
    c.material.isRIM = p.isRIM
    c.material.rimColor = p.rimColor

    c.material.isNormalSRGB = p.sRGB_normal

    c.material.matcapPercentR = p.matcapPercentR
    c.material.matcapPercentG = p.matcapPercentG
    c.material.matcapPercentB = p.matcapPercentB
    c.material.matcapPercentA = p.matcapPercentA
    c.material.matcapMaskPercent = p.matcapMaskPercent
    c.material.albedoPercent = p.albedoPercent
    c.material.glossPercent = p.glossPercent
    c.material.specularPercent = p.specularPercent
    c.material.normalPercent = p.normalPercent
    c.material.bumpPercent = p.bumpPercent
    c.material.reflectionPercent = p.reflectionPercent
    c.material.falloffPercent = p.falloffPercent
    c.material.maskPercent = p.maskPercent

    c.material.matcapTextureR = p.matcapTextureR
    c.material.matcapTextureG = p.matcapTextureG
    c.material.matcapTextureB = p.matcapTextureB
    c.material.matcapTextureA = p.matcapTextureA
    c.material.matcapMaskTexture = p.matcapMaskTexture
    c.material.albedoTexture = p.albedoTexture
    c.material.glossTexture = p.glossTexture
    c.material.specularTexture = p.specularTexture
    c.material.normalTexture = p.normalTexture
    c.material.bumpTexture = p.bumpTexture
    c.material.reflectionTexture = p.reflectionTexture
    c.material.falloffTexture = p.falloffTexture
    c.material.maskTexture = p.maskTexture

    c.vboData.vertInfo = newVertexInfoWithVertexData(p.vertex_coords.len, p.tex_coords.len, p.normals.len, p.tangents.len)

    let stride = int32( c.vboData.vertInfo.stride / sizeof(GLfloat) )
    let size = int32(p.vertex_coords.len * stride / 3)
    let vertexData = c.createVertexData(stride, size, p.vertex_coords, p.tex_coords, p.normals, p.tangents)

    c.createVBO(p.indices, vertexData)

    # TODO: Load skeleton

genSerializationCodeForComponent(MeshComponent)

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

import rod / viewport
method rayCast*(ns: MeshComponent, r: Ray, distance: var float32): bool =
    let distToCam = (ns.node.worldPos - ns.node.sceneView.camera.node.worldPos).length()
    if distToCam < 0.1:
        return false

    result = procCall ns.Component.rayCast(r, distance)
