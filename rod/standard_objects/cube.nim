import nimx.matrixes
import nimx.types
import rod.rod_types
import rod.node
import rod.component.mesh_component
import rod.component.material
import rod.vertex_data_info
import opengl

proc fillVertexBuffers(vertCoords, texCoords, normals: var seq[float32]) =
    #front
    vertCoords.add([-1.0f, -1.0f, -1.0f])
    vertCoords.add([-1.0f,  1.0f, -1.0f])
    vertCoords.add([ 1.0f,  1.0f, -1.0f])
    vertCoords.add([ 1.0f, -1.0f, -1.0f])

    for i in 0 .. 3:
        normals.add([ 0.0f, 0.0f, -1.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #right
    vertCoords.add([ 1.0f, -1.0f, -1.0f])
    vertCoords.add([ 1.0f,  1.0f, -1.0f])
    vertCoords.add([ 1.0f,  1.0f,  1.0f])
    vertCoords.add([ 1.0f, -1.0f,  1.0f])

    for i in 0 .. 3:
        normals.add([ 1.0f, 0.0f, 0.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #back
    vertCoords.add([ 1.0f, -1.0f, 1.0f])
    vertCoords.add([ 1.0f,  1.0f, 1.0f])
    vertCoords.add([-1.0f,  1.0f, 1.0f])
    vertCoords.add([-1.0f, -1.0f, 1.0f])

    for i in 0 .. 3:
        normals.add([ 0.0f, 0.0f, 1.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #left
    vertCoords.add([-1.0f, -1.0f,  1.0f])
    vertCoords.add([-1.0f,  1.0f,  1.0f])
    vertCoords.add([-1.0f,  1.0f, -1.0f])
    vertCoords.add([-1.0f, -1.0f, -1.0f])

    for i in 0 .. 3:
        normals.add([-1.0f, 0.0f, 1.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #top
    vertCoords.add([-1.0f, 1.0f, -1.0f])
    vertCoords.add([-1.0f, 1.0f,  1.0f])
    vertCoords.add([ 1.0f, 1.0f,  1.0f])
    vertCoords.add([ 1.0f, 1.0f, -1.0f])

    for i in 0 .. 3:
        normals.add([0.0f, 1.0f, 0.0f])

    texCoords.add([ 0.0f, 0.0f])
    texCoords.add([ 1.0f, 0.0f])
    texCoords.add([ 1.0f, 1.0f])
    texCoords.add([ 0.0f, 1.0f])

    #bottom
    vertCoords.add([-1.0f, -1.0f,  1.0f])
    vertCoords.add([-1.0f, -1.0f, -1.0f])
    vertCoords.add([ 1.0f, -1.0f, -1.0f])
    vertCoords.add([ 1.0f, -1.0f,  1.0f])

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

proc newCube*(): Node =
    result = newNode("Cube")
    let mesh = result.addComponent(MeshComponent)

    var vertCoords = newSeq[float32]()
    var texCoords = newSeq[float32]()
    var normals = newSeq[float32]()
    var indices = newSeq[GLushort]()

    fillVertexBuffers(vertCoords, texCoords, normals)
    fillIndexBuffer(indices)

    mesh.vboData.vertInfo = newVertexInfoWithVertexData(vertCoords.len, texCoords.len, normals.len, 0)

    let stride = int32( mesh.vboData.vertInfo.stride / sizeof(GLfloat) )
    let size = int32(vertCoords.len * stride / 3)
    var vertexData = newSeq[GLfloat](size)
    for i in 0 ..< int32(vertCoords.len / 3):
        var offset = 0
        vertexData[stride * i + 0] = vertCoords[3*i + 0]
        vertexData[stride * i + 1] = vertCoords[3*i + 1]
        vertexData[stride * i + 2] = vertCoords[3*i + 2]
        mesh.checkMinMax(vertCoords[3*i + 0], vertCoords[3*i + 1], vertCoords[3*i + 2])
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

    mesh.createVBO(indices, vertexData)

    mesh.material.ambient = newColor(1.0, 1.0, 1.0, 0.2)
    mesh.material.diffuse = newColor(1.0, 1.0, 1.0, 1.0)
