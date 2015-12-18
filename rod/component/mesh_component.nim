import rod.component

import nimx.image
import nimx.resource
import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.system_logger
import nimasset.obj
import strutils

import rod.component.material
import rod.component.light
import rod.vertex_data_info

when not defined(ios) and not defined(android) and not defined(js):
    import opengl

import streams

type MeshComponent* = ref object of Component
    resourceName: string
    indexBuffer*: GLuint
    vertexBuffer*: GLuint
    numberOfIndices*: GLsizei
    loadFunc: proc()
    vertInfo*: VertexDataInfo
    material*: Material

method init*(m: MeshComponent) =
    m.material = newDefaultMaterial()
    procCall m.Component.init()

proc applyLight*(m: MeshComponent) = 
    m.material.light = cast[LightSource](m.node.mViewport.light)

proc setInstansedVBOAttributes*(m: MeshComponent, indBuffer, vertBuffer: GLuint, numOfIndices: GLsizei, vInfo: VertexDataInfo) = 
    m.indexBuffer = indBuffer
    m.vertexBuffer = vertBuffer
    m.numberOfIndices = numOfIndices
    m.vertInfo = vInfo

proc mergeIndexes(vertexData, texCoordData, normalData: openarray[GLfloat], vertexAttrData: var seq[GLfloat], vi, ti, ni: int): GLushort =
    var attributesPerVertex: int = 0

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

proc loadMeshComponent(m: MeshComponent, resourceName: string) = 
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
                indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi0 - 1, uvIndex(ti0, vi0), ni0 - 1))
                indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi1 - 1, uvIndex(ti1, vi1), ni1 - 1))
                indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi2 - 1, uvIndex(ti2, vi2), ni2 - 1))

            loader.loadMeshData(s, addVertex, addTexCoord, addNormal, addFace)
            s.close()

            #TODO add binormal tangent
            m.vertInfo = newVertexInfoWithVertexData(vertexData.len(), texCoordData.len(), normalData.len())

            let gl = currentContext().gl
            m.indexBuffer = gl.createBuffer()
            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.indexBuffer)
            gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

            m.vertexBuffer = gl.createBuffer()
            gl.bindBuffer(gl.ARRAY_BUFFER, m.vertexBuffer)
            gl.bufferData(gl.ARRAY_BUFFER, vertexAttrData, gl.STATIC_DRAW)
            m.numberOfIndices = indexData.len.GLsizei
        if currentContext().isNil:
            m.loadFunc = loadFunc
        else:
            loadFunc()

proc loadMeshComponentWithResource*(m: MeshComponent, resourceName: string) =
    m.loadFunc = proc() =
        m.loadMeshComponent(resourceName)

proc newMeshComponentWithResource*(resourceName: string): MeshComponent =
    result.new()
    result.loadMeshComponentWithResource(resourceName)

proc loadMeshQuad(m: MeshComponent, v1, v2, v3, v4: Vector3, t1, t2, t3, t4: Point) = 
    let gl = currentContext().gl
    let vertexData = [
        v1[0], v1[1], v1[2], t1.x, t1.y,
        v2[0], v2[1], v2[2], t2.x, t2.y,
        v3[0], v3[1], v3[2], t3.x, t3.y,
        v4[0], v4[1], v4[2], t4.x, t4.y
        ]
    let indexData = [0.GLushort, 1, 2, 2, 3, 0]

    m.vertInfo = newVertexInfoWithVertexData(3, 2)

    m.indexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexData, gl.STATIC_DRAW)

    m.vertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, m.vertexBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, vertexData, gl.STATIC_DRAW)
    m.numberOfIndices = indexData.len.GLsizei

proc meshComponentWithQuad*(m: MeshComponent, v1, v2, v3, v4: Vector3, t1, t2, t3, t4: Point) =
    m.loadFunc = proc() =
        m.loadMeshQuad(v1, v2, v3, v4, t1, t2, t3, t4)

proc newMeshComponentWithQuad*(v1, v2, v3, v4: Vector3, t1, t2, t3, t4: Point): MeshComponent =
    result.new()
    result.meshComponentWithQuad(v1, v2, v3, v4, t1, t2, t3, t4)

proc load(mc: MeshComponent) =
    if not mc.loadFunc.isNil:
        mc.loadFunc()
        mc.loadFunc = nil

method draw*(m: MeshComponent) =
    let c = currentContext()
    let gl = c.gl

    if m.indexBuffer == 0:
        m.load()
        if m.indexBuffer == 0:
            return

    gl.bindBuffer(gl.ARRAY_BUFFER, m.vertexBuffer)
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.indexBuffer)

    m.material.updateVertexAttributesSetup(m.vertInfo)
    
    m.material.updateTransformSetup(m.node.translation, m.node.rotation, m.node.scale)

    m.material.updateSetup()

    gl.drawElements(gl.TRIANGLES, m.numberOfIndices, gl.UNSIGNED_SHORT)

    when defined(js):
        {.emit: """
        `gl`.bindBuffer(`gl`.ELEMENT_ARRAY_BUFFER, null);
        `gl`.bindBuffer(`gl`.ARRAY_BUFFER, null);
        """.}
    else:
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
        gl.bindBuffer(gl.ARRAY_BUFFER, 0)
    when not defined(ios) and not defined(android) and not defined(js):
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    #TODO to default settings
    gl.disable(gl.DEPTH_TEST)
    gl.activeTexture(gl.TEXTURE0)

registerComponent[MeshComponent]()
