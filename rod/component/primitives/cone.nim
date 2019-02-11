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

type ConeComponent* = ref object of MeshComponent
    mRadius1: float32
    mRadius2: float32
    mHeight: float32
    mSegments: int32

ConeComponent.properties:
    mRadius1
    mRadius2
    mHeight
    mSegments

proc fillBuffers(c: ConeComponent, vertCoords, texCoords, normals: var seq[float32], indices: var seq[GLushort]) =
    let angle_step = 2.0 * PI.float32 / c.mSegments.float32
    var angle = 0.0
    var v0, v1, v2, v3: Vector3
    var index_offset = 0

    # cone body
    while angle <= 2 * PI + angle_step:
        v0 = newVector(c.mRadius1 * cos(angle).float32, 0.0,    c.mRadius1 * sin(angle))
        v1 = newVector(c.mRadius2 * cos(angle).float32, c.mHeight, c.mRadius2 * sin(angle))
        vertCoords.add(v0)
        vertCoords.add(v1)

        texCoords.add([0.0.float32, 0.0])
        texCoords.add([1.0.float32, 1.0])

        normals.add([cos(angle).float32, 0.0, sin(angle)])
        normals.add([cos(angle).float32, 0.0, sin(angle)])

        angle += angle_step

    for i in 0 ..< c.mSegments:
        indices.add([(2*i + 0).GLushort, (2*i + 1).GLushort, (2*i + 2).GLushort])
        indices.add([(2*i + 3).GLushort, (2*i + 2).GLushort, (2*i + 1).GLushort])

    index_offset = int(vertCoords.len() / 3)

    # # cap bottom
    # # central vertex
    vertCoords.add([0.0.float32, 0.0, 0.0])
    texCoords.add([0.0.float32, 0.0])
    normals.add([0.0.float32, -1.0, 0.0])
    angle = 0.0

    for i in 0 .. c.mSegments:
        vertCoords.add([c.mRadius1 * cos(angle).float32, 0.0, c.mRadius1 * sin(angle)])
        texCoords.add([0.0.float32, 0.0])
        normals.add([0.0.float32, -1.0, 0.0])
        angle += angle_step

        if i < c.mSegments:
            indices.add([index_offset.GLushort, (i + index_offset + 1).GLushort, (i + index_offset + 2).GLushort])

    index_offset = int(vertCoords.len() / 3)

    # cap top
    # central vertex
    vertCoords.add([0.0.float32, c.mHeight, 0.0])
    texCoords.add([0.0.float32, 0.0])
    normals.add([0.0.float32, 1.0, 0.0])
    angle = 0.0

    for i in 0 .. c.mSegments:
        vertCoords.add([c.mRadius2 * cos(angle).float32, c.mHeight, c.mRadius2 * sin(angle)])
        texCoords.add([0.0.float32, 0.0])
        normals.add([0.0.float32, 1.0, 0.0])
        angle += angle_step

        if i < c.mSegments:
            indices.add([index_offset.GLushort, (i + index_offset + 2).GLushort, (i + index_offset + 1).GLushort])


method init*(c: ConeComponent) =
    procCall c.MeshComponent.init()
    c.mRadius1 = 1.0
    c.mRadius2 = 1.0
    c.mHeight = 4.0
    c.mSegments = 12

    c.material.ambient = newColor(1.0, 1.0, 1.0, 0.2)
    c.material.diffuse = newColor(1.0, 1.0, 1.0, 1.0)


proc generateMesh*(c: ConeComponent) =
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

template radius1*(cc: ConeComponent): float = c.mRadius1
template `radius1=`*(cc: ConeComponent, v: float) =
    cc.mRadius1 = v
    cc.generateMesh()

template radius2*(cc: ConeComponent): float = c.mRadius2
template `radius2=`*(cc: ConeComponent, v: float) =
    cc.mRadius2 = v
    cc.generateMesh()

template height*(cc: ConeComponent): float = c.mHeight
template `height=`*(cc: ConeComponent, v: float) =
    cc.mHeight = v
    cc.generateMesh()

template segments*(cc: ConeComponent): int = c.mSegments.int
template `segments=`*(cc: ConeComponent, v: int) =
    cc.mSegments = v.int32
    cc.generateMesh()

method componentNodeWasAddedToSceneView*(c: ConeComponent) =
    c.generateMesh()

method deserialize*(c: ConeComponent, j: JsonNode, s: Serializer) =
    if j.isNil:
        return

    s.deserializeValue(j, "radius1", c.radius1)
    s.deserializeValue(j, "radius2", c.radius2)
    s.deserializeValue(j, "height", c.height)
    s.deserializeValue(j, "segments", c.segments)

method serialize*(c: ConeComponent, s: Serializer): JsonNode =
    result = newJObject()
    result.add("radius1", s.getValue(c.radius1))
    result.add("radius2", s.getValue(c.radius2))
    result.add("height", s.getValue(c.height))
    result.add("segments", s.getValue(c.segments))

method visitProperties*(c: ConeComponent, p: var PropertyVisitor) =
    p.visitProperty("radius1", c.radius1)
    p.visitProperty("radius2", c.radius2)
    p.visitProperty("height", c.height)
    p.visitProperty("segments", c.segments)
    procCall c.MeshComponent.visitProperties(p)

genSerializationCodeForComponent(ConeComponent)
registerComponent(ConeComponent, "Primitives")
