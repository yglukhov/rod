import opengl
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

type CubeComponent* = ref object of MeshComponent
    size: Vector3

CubeComponent.properties:
    size

proc fillVertexBuffers(vertCoords, texCoords, normals: var seq[float32], size: Vector3) =
    #front
    vertCoords.add([-size.x, -size.y, -size.z])
    vertCoords.add([-size.x,  size.y, -size.z])
    vertCoords.add([ size.x,  size.y, -size.z])
    vertCoords.add([ size.x, -size.y, -size.z])

    for i in 0 .. 3:
        normals.add([ 0.0f, 0.0f, -1.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #right
    vertCoords.add([ size.x, -size.y, -size.z])
    vertCoords.add([ size.x,  size.y, -size.z])
    vertCoords.add([ size.x,  size.y,  size.z])
    vertCoords.add([ size.x, -size.y,  size.z])

    for i in 0 .. 3:
        normals.add([ 1.0f, 0.0f, 0.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #back
    vertCoords.add([ size.x, -size.y, size.z])
    vertCoords.add([ size.x,  size.y, size.z])
    vertCoords.add([-size.x,  size.y, size.z])
    vertCoords.add([-size.x, -size.y, size.z])

    for i in 0 .. 3:
        normals.add([ 0.0f, 0.0f, 1.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #left
    vertCoords.add([-size.x, -size.y,  size.z])
    vertCoords.add([-size.x,  size.y,  size.z])
    vertCoords.add([-size.x,  size.y, -size.z])
    vertCoords.add([-size.x, -size.y, -size.z])

    for i in 0 .. 3:
        normals.add([-1.0f, 0.0f, 1.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #top
    vertCoords.add([-size.x, size.y, -size.z])
    vertCoords.add([-size.x, size.y,  size.z])
    vertCoords.add([ size.x, size.y,  size.z])
    vertCoords.add([ size.x, size.y, -size.z])

    for i in 0 .. 3:
        normals.add([0.0f, 1.0f, 0.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #bottom
    vertCoords.add([-size.x, -size.y,  size.z])
    vertCoords.add([-size.x, -size.y, -size.z])
    vertCoords.add([ size.x, -size.y, -size.z])
    vertCoords.add([ size.x, -size.y,  size.z])

    for i in 0 .. 3:
        normals.add([0.0f, -1.0f, 0.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

proc fillIndexBuffer(indices: var seq[GLushort]) =
    #front
    indices.add([0.GLushort, 1, 2])
    indices.add([3.GLushort, 0, 2])

    #right
    indices.add([4.GLushort, 5, 6])
    indices.add([7.GLushort, 4, 6])

    #back
    indices.add([8.GLushort, 9, 10])
    indices.add([11.GLushort, 8, 10])

    #left
    indices.add([12.GLushort, 13, 14])
    indices.add([15.GLushort, 12, 14])

    #top
    indices.add([16.GLushort, 17, 18])
    indices.add([19.GLushort, 16, 18])

    #bottom
    indices.add([20.GLushort, 21, 22])
    indices.add([23.GLushort, 20, 22])

method init*(c: CubeComponent) =
    procCall c.MeshComponent.init()
    c.size = newVector3(1.0, 1.0, 1.0)

proc generateMesh(c: CubeComponent) =
    let mesh = c
    var vertCoords = newSeq[float32]()
    var texCoords = newSeq[float32]()
    var normals = newSeq[float32]()
    var indices = newSeq[GLushort]()

    fillVertexBuffers(vertCoords, texCoords, normals, c.size)
    fillIndexBuffer(indices)

    mesh.vboData.minCoord = newVector3(high(int).Coord, high(int).Coord, high(int).Coord)
    mesh.vboData.maxCoord = newVector3(low(int).Coord, low(int).Coord, low(int).Coord)
    mesh.vboData.vertInfo = newVertexInfoWithVertexData(vertCoords.len, texCoords.len, normals.len, 0)

    let stride = int32( mesh.vboData.vertInfo.stride / sizeof(GLfloat) )
    let size = int32(vertCoords.len * stride / 3)
    var vertexData = c.createVertexData(stride, size, vertCoords, texCoords, normals, nil)
    mesh.createVBO(indices, vertexData)

    mesh.material.ambient = newColor(1.0, 1.0, 1.0, 0.2)
    mesh.material.diffuse = newColor(1.0, 1.0, 1.0, 1.0)

method componentNodeWasAddedToSceneView*(c: CubeComponent) =
    c.generateMesh()

method deserialize*(c: CubeComponent, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "size", c.size)

method serialize*(c: CubeComponent, s: Serializer): JsonNode =
    result = newJObject()
    result.add("size", s.getValue(c.size))

method visitProperties*(c: CubeComponent, p: var PropertyVisitor) =
    template sizeAux(cc: CubeComponent): Vector3 = c.size
    template `sizeAux=`(cc: CubeComponent, v: Vector3) =
        cc.size = v
        cc.generateMesh()

    p.visitProperty("size", c.sizeAux)
    procCall c.MeshComponent.visitProperties(p)

genSerializationCodeForComponent(CubeComponent)
registerComponent(CubeComponent, "Primitives")
