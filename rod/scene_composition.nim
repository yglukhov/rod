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
    vx, vy, vz, nx, ny, nz: float

proc hash(v: VertexNormal): Hash =
    result = v.vx.hash() !& v.vy.hash() !& v.vz.hash() !& v.nx.hash() !& v.ny.hash() !& v.nz.hash()
    result = !$result

proc mergeIndexes(vertexData, texCoordData, normalData: openarray[GLfloat], vertexAttrData: var seq[GLfloat], vi, ni, ti: int, 
                  vertexesHash: var Table[VertexNormal, GLushort], tgX = 0.0, tgY = 0.0, tgZ: float32 = 0.0, bNeedTangent: bool = false): GLushort = 
    var attributesPerVertex: int = 0
    attributesPerVertex += 3
    if texCoordData.len > 0:
        attributesPerVertex += 2
    if normalData.len > 0:
        attributesPerVertex += 3

    var v: VertexNormal
    v.vx = vertexData[vi * 3 + 0]
    v.vy = vertexData[vi * 3 + 1]
    v.vz = vertexData[vi * 3 + 2]
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
                vertexAttrData.add(texCoordData[vi * 2 + 0])
                vertexAttrData.add(1.0 - texCoordData[vi * 2 + 1])
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
            var texLocationSplited = img.location.split('/')
            result = texLocationSplited[texLocationSplited.len() - 1]

proc loadSceneAsync*(resourceName: string, handler: proc(n: Node3D)) =
    loadResourceAsync resourceName, proc(s: Stream) =
        var loader: ColladaLoader

        let colladaRootNode = loader.load(s)
        s.close()

        let res = newNode(colladaRootNode.name)

        var i = 0
        for child in colladaRootNode.childNodesGeometry:
            let childNode = res.newChild(child.name)

            let nodeTranslation = parseMatrix4(colladaRootNode.childNodesMatrices[i])
            childNode.translation = newVector(nodeTranslation[3], nodeTranslation[7], nodeTranslation[11])
            inc(i)
            #TODO scene translation
            
            let childMesh = childNode.component(MeshComponent)

            var childColladaMaterial: ColladaMaterial

            for mat in colladaRootNode.childNodesMaterial:
                if mat.name.contains(child.materialName):
                    childColladaMaterial = mat
            
            childMesh.material.setAmbientColor(childColladaMaterial.ambient[0], childColladaMaterial.ambient[1], childColladaMaterial.ambient[2], childColladaMaterial.ambient[3])
            childMesh.material.setEmissionColor(childColladaMaterial.emission[0], childColladaMaterial.emission[1], childColladaMaterial.emission[2], childColladaMaterial.emission[3])
            childMesh.material.setDiffuseColor(childColladaMaterial.diffuse[0], childColladaMaterial.diffuse[1], childColladaMaterial.diffuse[2], childColladaMaterial.diffuse[3])
            childMesh.material.setSpecularColor(childColladaMaterial.specular[0], childColladaMaterial.specular[1], childColladaMaterial.specular[2], childColladaMaterial.specular[3])
            childMesh.material.setShininess(childColladaMaterial.shininess)
            childMesh.material.setReflectivity(childColladaMaterial.reflectivity)
            if childColladaMaterial.transparency < 1.0:
                childMesh.material.blendEnable = false
            #TODO 
            # reflective*: Vector4
            # transparent*: Vector4
            # transparency*: float32
            # transparentsTextureName*: string

            if childColladaMaterial.diffuseTextureName != nil:
                var texLocation = colladaRootNode.getTextureLocationByName(childColladaMaterial.diffuseTextureName)
                if texLocation != nil:
                    childMesh.material.albedoTexture = imageWithResource("collada/" & texLocation)
                
            if childColladaMaterial.reflectiveTextureName != nil:
                var texLocation = colladaRootNode.getTextureLocationByName(childColladaMaterial.reflectiveTextureName)
                if texLocation != nil:
                    childMesh.material.reflectionTexture = imageWithResource("collada/" & texLocation)

                    #TODO add other material texture
                    childMesh.material.falloffTexture = imageWithResource("collada/baloon_star_falloff.png")
                    childMesh.material.normalTexture = imageWithResource("collada/baloon_star_normals.png")

            if childColladaMaterial.specularTextureName != nil:
                var texLocation = colladaRootNode.getTextureLocationByName(childColladaMaterial.specularTextureName)
                if texLocation != nil:
                    childMesh.material.specularTexture = imageWithResource("collada/" & texLocation)

            let bNeedComputeTangentData = if childMesh.material.normalTexture.isNil(): false else: true

            var vertexAttrData = newSeq[GLfloat]()
            var indexData = newSeq[GLushort]()

            prepareVBO(child.vertices, child.texcoords, child.normals, child.triangles, vertexAttrData, indexData,
                       child.faceAccessor.vertexOfset, child.faceAccessor.normalOfset, child.faceAccessor.texcoordOfset, bNeedComputeTangentData)

            childMesh.vertInfo = newVertexInfoWithVertexData(child.vertices.len, child.texcoords.len, child.normals.len, if bNeedComputeTangentData: 3 else: 0)
            childMesh.createVBO(indexData, vertexAttrData)
        handler(res)
