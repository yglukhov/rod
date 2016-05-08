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

import rod.dae_animation

import nimx.image
import nimx.resource
import nimx.resource_cache
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

import math

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

proc mergeIndexes(m: MeshComponent, vertexData, texCoordData, normalData: openarray[GLfloat], vertexAttrData: var seq[GLfloat], vi, ni, ti: int,
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
        m.checkMinMax(vertexData[vi * 3 + 0], vertexData[vi * 3 + 1], vertexData[vi * 3 + 2])

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

proc prepareVBO(m: MeshComponent, vertexData, texCoordData, normalData: openarray[GLfloat], faces: seq[int],
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

            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi0, ni0, ti0, vertexesHash, tangent.x, tangent.y, tangent.z, true))
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi1, ni1, ti1, vertexesHash, tangent.x, tangent.y, tangent.z, true))
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi2, ni2, ti2, vertexesHash, tangent.x, tangent.y, tangent.z, true))
        else:
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi0, ni0, ti0, vertexesHash))
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi1, ni1, ti1, vertexesHash))
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi2, ni2, ti2, vertexesHash))

        i += faceStep

proc getTextureLocationByName(cs: ColladaScene, texName: string): string =
    for img in cs.childNodesImages:
        if texName.contains(img.name):
            result = img.location

proc parseArray4(source: string): array[0 .. 3, float32] =
    var i = 0
    for it in split(source):
        result[i] = parseFloat(it)
        inc(i)

proc parseArray3(source: string): array[0 .. 2, float32] =
    var i = 0
    for it in split(source):
        result[i] = parseFloat(it)
        inc(i)

proc setupFromColladaNode(cn: ColladaNode, colladaScene: ColladaScene): Node =
    result = newNode(cn.name)
    var materialInited = false
    var geometryInited = false
    var childColladaMaterial: ColladaMaterial
    var childColladaGeometry: ColladaGeometry
    var nodeMesh: MeshComponent

    if cn.matrix != nil:
        let modelMatrix = parseMatrix4(cn.matrix)

        var translation: Vector3
        var scale: Vector3
        var rotation: Vector4

        if modelMatrix.tryGetTranslationFromModel(translation) and modelMatrix.tryGetScaleRotationFromModel(scale, rotation):
            result.scale = scale
            result.translation = translation
            result.rotation = newQuaternion(rotation[0], rotation[1], rotation[2], rotation[3])
    else:
        if cn.scale != nil:
            let scale = parseArray3(cn.scale)
            result.scale = newVector3(scale[0], scale[1], scale[2])

        if cn.translation != nil:
            let translation = parseArray3(cn.translation)
            result.translation = newVector3(translation[0], translation[1], translation[2])

        var finalRotation = newQuaternion(0, 0, 0, 1)

        if cn.rotationX != nil:
            let rotationX = parseArray4(cn.rotationX)
            finalRotation *= aroundX(rotationX[3])
        if cn.rotationY != nil:
            let rotationY = parseArray4(cn.rotationY)
            finalRotation *= aroundY(rotationY[3])
        if cn.rotationZ != nil:
            let rotationZ = parseArray4(cn.rotationZ)
            finalRotation *= aroundZ(rotationZ[3])

        result.rotation = finalRotation

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
        nodeMesh.material.emission = newColor(childColladaMaterial.emission[0], childColladaMaterial.emission[1], childColladaMaterial.emission[2], childColladaMaterial.emission[3])
        nodeMesh.material.ambient = newColor(childColladaMaterial.ambient[0], childColladaMaterial.ambient[1], childColladaMaterial.ambient[2], childColladaMaterial.ambient[3])
        nodeMesh.material.diffuse = newColor(childColladaMaterial.diffuse[0], childColladaMaterial.diffuse[1], childColladaMaterial.diffuse[2], childColladaMaterial.diffuse[3])
        nodeMesh.material.specular = newColor(childColladaMaterial.specular[0], childColladaMaterial.specular[1], childColladaMaterial.specular[2], childColladaMaterial.specular[3])
        if childColladaMaterial.shininess > 1.0:
            nodeMesh.material.shininess = childColladaMaterial.shininess
        else:
            nodeMesh.material.shininess = 1.0

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
                nodeMesh.material.diffuse = newColor(1.0, 1.0, 1.0, 1.0)

        if childColladaMaterial.reflectiveTextureName != nil:
            var texName = colladaScene.getTextureLocationByName(childColladaMaterial.reflectiveTextureName)
            if texName != nil:
                nodeMesh.material.reflectionTexture = imageWithResource(texName)
                nodeMesh.material.reflectivity = childColladaMaterial.reflectivity

        if childColladaMaterial.specularTextureName != nil:
            var texName = colladaScene.getTextureLocationByName(childColladaMaterial.specularTextureName)
            if texName != nil:
                nodeMesh.material.specularTexture = imageWithResource(texName)
        # normalmap tex seted manually in dae file
        if childColladaMaterial.normalmapTextureName != nil:
            var texName = colladaScene.getTextureLocationByName(childColladaMaterial.normalmapTextureName)
            if texName != nil:
                nodeMesh.material.normalTexture = imageWithResource(texName)

    if geometryInited:
        nodeMesh.resourceName = childColladaGeometry.name

        var instanceWrd = "instance"
        if childColladaGeometry.name.contains(instanceWrd):
            var instanceName = ""
            var j = 0
            while j < childColladaGeometry.name.len:
                var i = 0
                while i < instanceWrd.len:
                    if childColladaGeometry.name[j+i] == instanceWrd[i]:
                        inc i
                    else:
                        break
                if i != instanceWrd.len:
                    instanceName &= $childColladaGeometry.name[j]
                    inc j
                else:
                    break
            instanceName &= instanceWrd
            nodeMesh.resourceName = instanceName

        if not vboCache.contains(nodeMesh.resourceName):

            let bNeedComputeTangentData = if nodeMesh.material.normalTexture.isNil(): false else: true

            var vertexAttrData = newSeq[GLfloat]()
            var indexData = newSeq[GLushort]()

            nodeMesh.prepareVBO(childColladaGeometry.vertices, childColladaGeometry.texcoords, childColladaGeometry.normals, childColladaGeometry.triangles, vertexAttrData, indexData,
                                childColladaGeometry.faceAccessor.vertexOfset, childColladaGeometry.faceAccessor.normalOfset, childColladaGeometry.faceAccessor.texcoordOfset, bNeedComputeTangentData)
            nodeMesh.vboData.vertInfo = newVertexInfoWithVertexData(childColladaGeometry.vertices.len, childColladaGeometry.texcoords.len, childColladaGeometry.normals.len, if bNeedComputeTangentData: 3 else: 0)
            nodeMesh.createVBO(indexData, vertexAttrData)

            vboCache[nodeMesh.resourceName] = nodeMesh.vboData
        else:
            nodeMesh.vboData = vboCache[nodeMesh.resourceName]

    for it in cn.children:
        result.addChild(setupFromColladaNode(it, colladaScene))

var gScenesResCache = initResourceCache[ColladaScene]()

proc loadColladaFromStream(s: Stream, resourceName: string): ColladaScene =
    var loader: ColladaLoader
    result = loader.load(s)
    s.close()

proc loadSceneAsync*(resourceName: string, handler: proc(n: Node3D)) =
    let colladaScene = gScenesResCache.get(resourceName)

    if colladaScene.isNil:
        resourceNotCached(resourceName)

        loadResourceAsync resourceName, proc(s: Stream) =
            pushParentResource(resourceName)

            let colladaScene = loadColladaFromStream(s, resourceName)
            gScenesResCache.registerResource(resourceName, colladaScene)

            let res = setupFromColladaNode(colladaScene.rootNode, colladaScene)
            for anim in colladaScene.animations:
                discard animationWithCollada(res, anim)

            popParentResource()
            handler(res)
    else:
        pushParentResource(resourceName)

        let res = setupFromColladaNode(colladaScene.rootNode, colladaScene)
        for anim in colladaScene.animations:
            discard animationWithCollada(res, anim)

        popParentResource()
        handler(res)

registerResourcePreloader(["dae"], proc(name: string, callback: proc()) =
    loadResourceAsync(name, proc(s: Stream) =
        pushParentResource(name)
        let colladaScene = loadColladaFromStream(s, name)
        popParentResource()
        gScenesResCache.registerResource(name, colladaScene)
        callback()
    )
)
