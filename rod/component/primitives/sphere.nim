import opengl
import math
import json

import nimx.matrixes
import nimx.types
import nimx.property_visitor

import rod.rod_types
import rod.node
import rod.component
import rod.component.mesh_component
import rod.component.material
import rod.vertex_data_info
import rod.tools.serializer
import rod / utils / [ property_desc, serialization_codegen ]

type SphereComponent* = ref object of MeshComponent
    radius: float32
    segments: int32

SphereComponent.properties:
    radius
    segments

proc fillBuffers(c: SphereComponent, vertCoords, texCoords, normals: var seq[float32], indices: var seq[GLushort]) =
    let segments = c.segments
    let segStep = 3.14 * 2.0f / float(segments * 2)
    var mR: Matrix4
    var tPos: Vector3

    for i in 0 .. segments * 2:
        vertCoords.add([ 0.0f, c.radius, 0.0f])
        normals.add([ 0.0f, 1.0f, 0.0f])
        var tx:float32 = (1.0f / (segments.float32 * 2.0)) * (segments.float32 * 2.0 - i.float32) - (0.5f / (segments.float32 * 2.0))
        texCoords.add([tx, 0.0f])

    for i in 0 .. segments * 2:
        vertCoords.add([ 0.0f, -c.radius, 0.0f])
        normals.add([ 0.0f, -1.0f, 0.0f])
        var tx: float32 = (1.0f / (segments.float32 * 2.0)) * (segments.float32 * 2.0 - i.float32) - (0.5f / (segments.float32 * 2.0))
        texCoords.add([tx, 1.0f])

    for i in 1 .. segments:
        var startVertex = int(vertCoords.len() / 3)

        for j in 0 .. segments * 2 + 1:
            mR.loadIdentity()
            mR.rotateY(segStep * j.float32)
            mR.rotateX(segStep * i.float32)
            var vec = newVector3(0.0, c.radius, 0.0)
            tPos = mR * vec

            vertCoords.add([tPos.x, tPos.y, tPos.z])
            var norm = tPos.normalized()
            normals.add([norm.x, norm.y, norm.z])
            var tx: float32 = (1.0f / (segments.float32 * 2.0)) * (segments.float32 * 2.0 - j.float32)
            var ty: float32 = (1.0f / segments.float32) * i.float32
            texCoords.add([tx, ty])

            if i == 1:
                if j != segments * 2:
                    indices.add(GLushort(startVertex + (j + 1)))
                    indices.add(j.GLushort)
                    indices.add(GLushort(startVertex + (j + 0)))

            if i == segments - 1:
                if j != segments * 2:
                    indices.add(GLushort(j + segments*2))
                    indices.add(GLushort(startVertex + (j + 1)))
                    indices.add(GLushort(startVertex + (j + 0)))

            if i != 1 and segments != 2:
                if j != segments * 2:
                    indices.add(GLushort(startVertex + (j + 1)))
                    indices.add(GLushort(startVertex - (segments * 2 + 1) + (j + 1)))
                    indices.add(GLushort(startVertex - (segments * 2 + 1) + (j + 0)))
                    indices.add(GLushort(startVertex + (j + 0)))
                    indices.add(GLushort(startVertex + (j + 1)))
                    indices.add(GLushort(startVertex - (segments * 2 + 1) + (j + 0)))

method init*(c: SphereComponent) =
    procCall c.MeshComponent.init()
    c.radius = 1.0
    c.segments = 15

proc generateMesh*(c: SphereComponent) =
    let mesh = c

    var vertCoords = newSeq[float32]()
    var texCoords = newSeq[float32]()
    var normals = newSeq[float32]()
    var indices = newSeq[GLushort]()

    c.fillBuffers(vertCoords, texCoords, normals, indices)

    mesh.vboData.minCoord = newVector3(high(int).Coord, high(int).Coord, high(int).Coord)
    mesh.vboData.maxCoord = newVector3(low(int).Coord, low(int).Coord, low(int).Coord)
    mesh.vboData.vertInfo = newVertexInfoWithVertexData(vertCoords.len, texCoords.len, normals.len, 0)

    let stride = int32( mesh.vboData.vertInfo.stride / sizeof(GLfloat) )
    let size = int32(vertCoords.len * stride / 3)
    var vertexData = c.createVertexData(stride, size, vertCoords, texCoords, normals, @[])

    mesh.createVBO(indices, vertexData)

    mesh.material.ambient = newColor(1.0, 1.0, 1.0, 0.2)
    mesh.material.diffuse = newColor(1.0, 1.0, 1.0, 1.0)

method componentNodeWasAddedToSceneView*(c: SphereComponent) =
    c.generateMesh()

method deserialize*(c: SphereComponent, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "radius", c.radius)
    s.deserializeValue(j, "segments", c.segments)

method serialize*(c: SphereComponent, s: Serializer): JsonNode =
    result = newJObject()
    result.add("radius", s.getValue(c.radius))
    result.add("segments", s.getValue(c.segments))

method visitProperties*(c: SphereComponent, p: var PropertyVisitor) =
    template radiusAux(cc: SphereComponent): float = c.radius
    template `radiusAux=`(cc: SphereComponent, v: float) =
        cc.radius = v
        cc.generateMesh()

    template segmentsAux(cc: SphereComponent): int32 = c.segments
    template `segmentsAux=`(cc: SphereComponent, v: int32) =
        cc.segments = v
        cc.generateMesh()

    p.visitProperty("radius", c.radiusAux)
    p.visitProperty("segments", c.segmentsAux)
    procCall c.MeshComponent.visitProperties(p)

genSerializationCodeForComponent(SphereComponent)
registerComponent(SphereComponent, "Primitives")
