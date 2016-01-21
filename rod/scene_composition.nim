import nimasset.collada

import rod.viewport
import rod.component.camera
import rod.node

import rod.component.mesh_component
import rod.vertex_data_info
import rod.component.material
import rod.component.light
import rod.component
import rod.rod_types
import rod.quaternion

import nimx.image
import nimx.resource
import nimx.context
import nimx.portable_gl
import nimx.window
import nimx.animation
import nimx.matrixes

import streams
import strutils
import algorithm
import tables
import hashes

proc parseVector4(source: string): Vector4 =
  var i = 0
  for it in split(source):
    result[i] = parseFloat(it)
    inc(i)

proc parseMatrix4(source: string): Matrix4 =
    var nodeMarix: array[16, float32]
    var i = 0
    for it in split(source):
        nodeMarix[i] = parseFloat(it)
        inc(i)
    result = nodeMarix


proc isNear(v1, v2: float32): bool =
    result = abs( v1 - v2 ) < 0.01.float32

proc isEqual(v0x, v0y, v0z, v1x, v1y, v1z: float32): bool =
    result = isNear(v0x, v1x) and isNear(v0y, v1y) and isNear(v0z, v1z)

type VertexNormal = object
    vx, vy, vz, nx, ny, nz, tx, ty: float

proc hash(v: VertexNormal): Hash =
    result = v.vx.hash() !& v.vy.hash() !& v.vz.hash() !& v.nx.hash() !& v.ny.hash() !& v.nz.hash() !& v.tx.hash() !& v.ty.hash()
    result = !$result

proc mergeIndexes(vertexData, texCoordData, normalData: openarray[GLfloat], vertexAttrData: var seq[GLfloat], vi, ni, ti: int,
                  vertexesHash: var Table[VertexNormal, GLushort], tgX = 0.0, tgY = 0.0, tgZ: float32 = 0.0, bNeedTangent: bool = false): GLushort =
    var v: VertexNormal
    v.vx = vertexData[vi * 3 + 0]
    v.vy = vertexData[vi * 3 + 1]
    v.vz = vertexData[vi * 3 + 2]
    var attributesPerVertex: int = 0
    attributesPerVertex += 3
    if texCoordData.len > 0:
        attributesPerVertex += 2
        v.tx = texCoordData[ti * 2 + 0]
        v.ty = texCoordData[ti * 2 + 1]
    if normalData.len > 0:
        attributesPerVertex += 3
        v.nx = normalData[ni * 3 + 0]
        v.ny = normalData[ni * 3 + 1]
        v.nz = normalData[ni * 3 + 2]

    if not vertexesHash.contains(v):
        vertexAttrData.add(vertexData[vi * 3 + 0])
        vertexAttrData.add(vertexData[vi * 3 + 1])
        vertexAttrData.add(vertexData[vi * 3 + 2])

        if texCoordData.len > 0:
            if ti != -1:
                vertexAttrData.add(texCoordData[ti * 2 + 0])
                vertexAttrData.add(1.0 - texCoordData[ti * 2 + 1])
            else:
                vertexAttrData.add(vertexData[vi * 2 + 0])
                vertexAttrData.add(1.0 - vertexData[vi * 2 + 1])
        if normalData.len > 0:
            if ni != -1:
                vertexAttrData.add(normalData[ni * 3 + 0])
                vertexAttrData.add(normalData[ni * 3 + 1])
                vertexAttrData.add(normalData[ni * 3 + 2])
            else:
                vertexAttrData.add(normalData[vi * 3 + 0])
                vertexAttrData.add(normalData[vi * 3 + 1])
                vertexAttrData.add(normalData[vi * 3 + 2])
        if bNeedTangent:
            vertexAttrData.add(tgX)
            vertexAttrData.add(tgY)
            vertexAttrData.add(tgZ)
            attributesPerVertex += 3

        result = GLushort(vertexAttrData.len / attributesPerVertex - 1)

        vertexesHash[v] = result
    else:
        result = vertexesHash[v]

proc prepareVBO(vertexData, texCoordData, normalData: openarray[GLfloat], faces: seq[int],
                vertexAttrData: var seq[GLfloat], indexData: var seq[GLushort],
                vertexOfset, normalOfset, texcoordOfset: int, bNeedComputeTangentData: bool = false) =
    var i = 0
    var stride = 1
    const coordPerVertex = 3
    if normalOfset != 0:
        inc(stride)
    if texcoordOfset != 0:
        inc(stride)
    var faceStep: int = stride * coordPerVertex

    var vertexesHash = initTable[VertexNormal, GLushort]()

    while i < faces.len:
        let
            vi0 = faces[i+vertexOfset]
            vi1 = faces[i+vertexOfset+stride]
            vi2 = faces[i+vertexOfset+2*stride]
            ni0 = faces[i+normalOfset]
            ni1 = faces[i+normalOfset+stride]
            ni2 = faces[i+normalOfset+2*stride]
            ti0 = faces[i+texcoordOfset]
            ti1 = faces[i+texcoordOfset+stride]
            ti2 = faces[i+texcoordOfset+2*stride]

        if bNeedComputeTangentData:
            var
                v0 = newVector3(vertexData[vi0 * 3 + 0], vertexData[vi0 * 3 + 1], vertexData[vi0 * 3 + 2])
                v1 = newVector3(vertexData[vi1 * 3 + 0], vertexData[vi1 * 3 + 1], vertexData[vi1 * 3 + 2])
                v2 = newVector3(vertexData[vi2 * 3 + 0], vertexData[vi2 * 3 + 1], vertexData[vi2 * 3 + 2])
                uv0 = newVector2(texCoordData[ti0 * 2 + 0], 1.0 - texCoordData[ti0 * 2 + 1])
                uv1 = newVector2(texCoordData[ti1 * 2 + 0], 1.0 - texCoordData[ti1 * 2 + 1])
                uv2 = newVector2(texCoordData[ti2 * 2 + 0], 1.0 - texCoordData[ti2 * 2 + 1])
                deltaPos1 = v1 - v0
                deltaPos2 = v2 - v0
                deltaUV1 = uv1 - uv0
                deltaUV2 = uv2 - uv0
                r = 1.0 / (deltaUV1.x * deltaUV2.y - deltaUV1.y * deltaUV2.x).float32
                tangent = (deltaPos1 * deltaUV2.y - deltaPos2 * deltaUV1.y) * r
                # bitangent = (deltaPos2 * deltaUV1.x - deltaPos1 * deltaUV2.x) * r

            tangent.normalize()
            # bitangent.normalize()

            indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi0, ni0, ti0, vertexesHash, tangent.x, tangent.y, tangent.z, true))
            indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi1, ni1, ti1, vertexesHash, tangent.x, tangent.y, tangent.z, true))
            indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi2, ni2, ti2, vertexesHash, tangent.x, tangent.y, tangent.z, true))
        else:
            indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi0, ni0, ti0, vertexesHash))
            indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi1, ni1, ti1, vertexesHash))
            indexData.add(mergeIndexes(vertexData, texCoordData, normalData, vertexAttrData, vi2, ni2, ti2, vertexesHash))

        i += faceStep

proc getTextureLocationByName(cs: ColladaScene, texName: string): string =
    for img in cs.childNodesImages:
        if texName.contains(img.name):
            result = img.location

proc setupFromColladaNode(cn: ColladaNode, colladaScene: ColladaScene): Node =
    result = newNode(cn.name)
    var materialInited = false
    var geometryInited = false
    var childColladaMaterial: ColladaMaterial
    var childColladaGeometry: ColladaGeometry
    var nodeMesh: MeshComponent

    if cn.matrix != nil:
        let nodeTranslation = parseMatrix4(cn.matrix)
        result.translation = newVector(nodeTranslation[3], nodeTranslation[7], nodeTranslation[11])

    if cn.geometry != nil:
        for geom in colladaScene.childNodesGeometry:
            if cn.geometry.contains(geom.name) or geom.name.contains(cn.geometry):
                childColladaGeometry = geom
                geometryInited = true
                nodeMesh = result.component(MeshComponent)

    if cn.material != nil:
        for mat in colladaScene.childNodesMaterial:
            if mat.name.contains(cn.material) or cn.material.contains(mat.name):
                childColladaMaterial = mat
                materialInited = true

    if materialInited:
        var transparency = childColladaMaterial.transparency
        if transparency < 1.0:
            nodeMesh.material.blendEnable = true
        nodeMesh.material.setEmissionColor(childColladaMaterial.emission[0], childColladaMaterial.emission[1], childColladaMaterial.emission[2], childColladaMaterial.emission[3])
        nodeMesh.material.setAmbientColor(childColladaMaterial.ambient[0], childColladaMaterial.ambient[1], childColladaMaterial.ambient[2], childColladaMaterial.ambient[3])
        nodeMesh.material.setDiffuseColor(childColladaMaterial.diffuse[0], childColladaMaterial.diffuse[1], childColladaMaterial.diffuse[2], childColladaMaterial.diffuse[3])
        nodeMesh.material.setSpecularColor(childColladaMaterial.specular[0], childColladaMaterial.specular[1], childColladaMaterial.specular[2], childColladaMaterial.specular[3])
        if childColladaMaterial.shininess > 1.0:
            nodeMesh.material.setShininess(childColladaMaterial.shininess)
        else:
            nodeMesh.material.setShininess(1.0)

        #TODO
        # reflective*: Vector4
        # transparent*: Vector4
        # transparentTextureName*: string
        # add other material texture
        # childMesh.material.falloffTexture = imageWithResource("")

        if childColladaMaterial.diffuseTextureName != nil:
            var texName = colladaScene.getTextureLocationByName(childColladaMaterial.diffuseTextureName)
            if texName != nil:
                nodeMesh.material.albedoTexture = imageWithResource(texName)

        if childColladaMaterial.reflectiveTextureName != nil:
            var texName = colladaScene.getTextureLocationByName(childColladaMaterial.reflectiveTextureName)
            if texName != nil:
                nodeMesh.material.reflectionTexture = imageWithResource(texName)
                nodeMesh.material.setReflectivity(childColladaMaterial.reflectivity)

        if childColladaMaterial.specularTextureName != nil:
            var texName = colladaScene.getTextureLocationByName(childColladaMaterial.specularTextureName)
            if texName != nil:
                nodeMesh.material.specularTexture = imageWithResource(texName)
        # normalmap tex seted manually in dae file
        if childColladaMaterial.normalmapTextureName != nil:
            var texName = colladaScene.getTextureLocationByName(childColladaMaterial.normalmapTextureName)
            if texName != nil:
                nodeMesh.material.normalTexture = imageWithResource(texName)
    # else:
    #     echo("material does not inited for ", cn.name, " node")

    if geometryInited:
        let bNeedComputeTangentData = if nodeMesh.material.normalTexture.isNil(): false else: true

        var vertexAttrData = newSeq[GLfloat]()
        var indexData = newSeq[GLushort]()

        prepareVBO(childColladaGeometry.vertices, childColladaGeometry.texcoords, childColladaGeometry.normals, childColladaGeometry.triangles, vertexAttrData, indexData,
                   childColladaGeometry.faceAccessor.vertexOfset, childColladaGeometry.faceAccessor.normalOfset, childColladaGeometry.faceAccessor.texcoordOfset, bNeedComputeTangentData)

        nodeMesh.vertInfo = newVertexInfoWithVertexData(childColladaGeometry.vertices.len, childColladaGeometry.texcoords.len, childColladaGeometry.normals.len, if bNeedComputeTangentData: 3 else: 0)
        nodeMesh.createVBO(indexData, vertexAttrData)
    # else:
    #     echo("geometry does not inited for ", cn.name, " node")

    for it in cn.childs:
        result.addChild(setupFromColladaNode(it, colladaScene))

proc loadSceneAsync*(resourceName: string, handler: proc(n: Node3D)) =
    loadResourceAsync resourceName, proc(s: Stream) =
        var loader: ColladaLoader

        pushParentResource(resourceName)
        defer: popParentResource()

        let colladaScene = loader.load(s)
        s.close()

        let res = setupFromColladaNode(colladaScene.rootNode, colladaScene)

        handler(res)
