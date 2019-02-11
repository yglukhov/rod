import nimx.matrixes
import nimx.types
import nimx.property_visitor

import rod.rod_types
import rod.component
import rod.component.mesh_component
import rod.component.material
import rod.vertex_data_info

import math, tables
import nimx.portable_gl

type MeshInfo = ref object
    vertices: seq[Vector3]
    triangles: seq[int]
    textCoords: seq[Vector2]

type Edge = tuple
    v1, v2: int

type Icosphere* = ref object of MeshComponent
    steps*: int
    radius*: float

proc icosahedron(r: float):MeshInfo

proc addTriangle(m: MeshInfo, tr: varargs[int])=
    for t in tr:
        m.triangles.add(t)

proc toGl(sv: seq[Vector3], r: float): seq[GLfloat]=
    result = newSeq[GLfloat]()
    for v in sv:
        result.add(v[0] * r)
        result.add(v[1] * r)
        result.add(v[2] * r)

proc toGl(sv: seq[Vector2]): seq[GLfloat]=
    result = newSeq[GLfloat]()
    for v in sv:
        result.add(v[0])
        result.add(v[1])


proc toGl(si: seq[int]): seq[GLushort]=
    result = newSeq[GLushort]()
    for i in si:
        result.add(i.GLushort)

proc getUVFromVert(vr: Vector3): Vector2=
    var icouv2 = newVector2(0,0)
    icouv2.x = (arctan2(vr.x, vr.z) + PI) / PI / 2.0
    icouv2.y = (arccos(vr.y) + PI) / PI - 1.0
    result = icouv2

proc subdivideEdge(f0, f1: int, v0,v1: Vector3,
    mesh: MeshInfo, divisions: var Table[Edge, int]):int=

    let edge = (v1: min(f0, f1), v2: max(f0, f1))
    if edge in divisions:
        return divisions[edge]

    var v = (v0 + v1)

    var norm = v.dot(v)
    var length = 1.0 / sqrt(norm)

    var vr = v * length

    let fl = mesh.vertices.len
    # vr.normalize()
    mesh.vertices.add(vr)

    mesh.textCoords.add(getUVFromVert(vr))

    divisions[edge] = fl

    return fl

proc subDivideMesh(meshIn: MeshInfo, meshOut: MeshInfo)=
    meshOut.vertices = meshIn.vertices
    meshOut.textCoords = meshIn.textCoords

    var divisions = initTable[Edge, int]()
    let triangles = (meshIn.triangles.len div 3)

    for i in 0 ..< triangles:

        let
            f0 = meshIn.triangles[i * 3]
            f1 = meshIn.triangles[i * 3 + 1]
            f2 = meshIn.triangles[i * 3 + 2]

        let
            v0 = meshIn.vertices[f0]
            v1 = meshIn.vertices[f1]
            v2 = meshIn.vertices[f2]

        let
            f3 = subdivideEdge(f0, f1, v0, v1, meshOut, divisions)
            f4 = subdivideEdge(f1, f2, v1, v2, meshOut, divisions)
            f5 = subdivideEdge(f2, f0, v2, v0, meshOut, divisions)

        meshOut.addTriangle(f0, f3, f5)
        meshOut.addTriangle(f3, f1, f4)
        meshOut.addTriangle(f5, f4, f2)
        meshOut.addTriangle(f3, f4, f5)

proc genUVCoords(m: MeshInfo, steps: int)=
    discard

proc debugInfo(m: MeshInfo)=

    echo "total vertices ", m.vertices.len, " total trinagles ", m.triangles.len div 3

proc genMesh(s: Icosphere)=

    var meshes: array[2, MeshInfo]
    meshes[0] = icosahedron(s.radius)
    meshes[1] = new(MeshInfo)
    meshes[1].triangles = @[]
    meshes[1].vertices = @[]

    var idx = 0
    for step in 0 ..< s.steps:
        var mIn = meshes[idx]

        idx = (idx + 1) mod 2
        var mOut = meshes[idx]
        mOut.vertices.setLen(0)
        mOut.triangles.setLen(0)
        subDivideMesh(mIn, mOut)

    var resMesh = meshes[idx]
    # resMesh.debugInfo()
    resMesh.genUVCoords(s.steps)

    var vertCoords = resMesh.vertices.toGl(s.radius)
    var normals = resMesh.vertices.toGl(1.0)
    var texCoords = resMesh.textCoords.toGl()
    var indices = resMesh.triangles.toGl()

    s.vboData.minCoord = newVector3(high(int).Coord, high(int).Coord, high(int).Coord)
    s.vboData.maxCoord = newVector3(low(int).Coord, low(int).Coord, low(int).Coord)

    s.vboData.vertInfo = newVertexInfoWithVertexData(vertCoords.len, texCoords.len, normals.len, 0)
    let stride = int32( s.vboData.vertInfo.stride / sizeof(GLfloat) )
    let size = int32(vertCoords.len * stride / 3)
    var vertexData = s.createVertexData(stride, size, vertCoords, texCoords, normals, @[])

    s.createVBO(indices, vertexData)

    s.material.ambient = newColor(1.0, 1.0, 1.0, 0.2)
    s.material.diffuse = newColor(1.0, 1.0, 1.0, 1.0)

method init*(s: Icosphere)=
    procCall s.MeshComponent.init()
    s.steps = 0
    s.radius = 15.0

method componentNodeWasAddedToSceneView*(s: Icosphere) =
    s.genMesh()

method visitProperties*(c: Icosphere, p: var PropertyVisitor) =
    procCall c.MeshComponent.visitProperties(p)

    template radiusAux(cc: Icosphere): float = c.radius
    template `radiusAux=`(cc: Icosphere, v: float) =
        cc.radius = v
        cc.genMesh()

    template segmentsAux(cc: Icosphere): int = c.steps
    template `segmentsAux=`(cc: Icosphere, v: int) =
        cc.steps = v
        cc.genMesh()

    p.visitProperty("radius", c.radiusAux)
    p.visitProperty("steps", c.segmentsAux)

proc icosahedron(r: float):MeshInfo =
    result.new()

    result.vertices = @[]
    result.triangles = @[]
    result.textCoords = @[]

    let theta = 26.56505117707799 * PI / 180.0;
    let stheta = sin(theta)
    let ctheta = cos(theta)

    result.vertices.add(newVector3(0,0,-1))
    template adtc(v: Vector3)=
        result.textCoords.add(getUVFromVert(v))
    adtc(result.vertices[0])

    let divider = PI / 5.0
    var phi = divider
    for i in 0 ..< 5:
        var v = newVector3()
        v.x = ctheta * cos(phi)
        v.y = ctheta * sin(phi)
        v.z = -stheta
        v.normalize()
        result.vertices.add(v)
        adtc(v)
        phi += 2.0 * divider

    phi = 0.0
    for i in 0 ..< 5:
        var v = newVector3()
        v.x = ctheta * cos(phi)
        v.y = ctheta * sin(phi)
        v.z = stheta
        v.normalize()
        result.vertices.add(v)
        adtc(v)
        phi += 2.0 * divider

    result.vertices.add(newVector3(0,0,1))
    adtc(result.vertices[^1])

    template at(tr: varargs[int])=
        result.addTriangle(tr)

    at 0, 2, 1
    at 0, 3, 2
    at 0, 4, 3
    at 0, 5, 4
    at 0, 1, 5

    at 1, 2, 7
    at 2, 3, 8
    at 3, 4, 9
    at 4, 5, 10
    at 5, 1, 6

    at 1, 7, 6
    at 2, 8, 7
    at 3, 9, 8
    at 4, 10, 9
    at 5, 6, 10

    at 6, 7, 11
    at 7, 8, 11
    at 8, 9, 11
    at 9, 10, 11
    at 10, 6, 11

registerComponent(Icosphere, "Primitives")
