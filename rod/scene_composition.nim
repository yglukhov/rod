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

import component.animation.skeleton

import nimx.image
import nimx.context
import nimx.portable_gl
import nimx.window
import nimx.animation
import nimx.matrixes
import nimx.assets.asset_loading
import nimx.assets.url_stream
import nimx.assets.asset_manager
import nimx.pathutils

import streams, strutils, algorithm, tables, hashes, math

proc parseVector4(source: string): Vector4 =
  var i = 0
  for it in split(source):
    result[i] = parseFloat(it)
    inc(i)

proc parseMatrix4(source: openarray[float32]): Matrix4 =
    var i = 0
    while i < result.len:
        result[i] = source[i]
        inc i

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
                  vertWeightsData: var seq[GLfloat], boneIDsData: var seq[GLfloat], skeleton: Skeleton, skinController: ColladaSkinController,
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

        # vertex bone weights
        if not skeleton.isNil and not skinController.isNil:
            var tempVertexWeights: array[4, float32]
            var weightAbs = 0.0

            for j in 0 ..< 4:
                if j < skinController.weightsPerVertex:
                    var bData: tuple[bone: string, weight: float32]
                    bData = skinController.boneAndWeightForVertex(vi, j)

                    if not bData.bone.isNil:
                        boneIDsData.add( Glfloat( skeleton.getBoneIdByName(bData.bone) ) )
                        tempVertexWeights[j] = bData.weight
                        weightAbs += bData.weight
                    else:
                        boneIDsData.add(0.0)
                else:
                    boneIDsData.add(0.0) # add bone ID
                # echo "v  ", v, " j  ", j,  "  bdata ", repr bData

            # normalize vertex weights
            for i in 0 ..< 4:
                vertWeightsData.add(tempVertexWeights[i] / weightAbs)

        result = GLushort(vertexAttrData.len / attributesPerVertex - 1)

        vertexesHash[v] = result
    else:
        result = vertexesHash[v]

proc prepareVBO(m: MeshComponent, cGeometry: ColladaGeometry,
                vertexAttrData: var seq[GLfloat], indexData: var seq[GLushort],
                vertWeightsData: var seq[GLfloat], boneIDsData: var seq[GLfloat], skeleton: Skeleton, skinController: ColladaSkinController,
                bNeedComputeTangentData: bool = false) =

    var vertexOfset = cGeometry.faceAccessor.vertexOfset
    var normalOfset = cGeometry.faceAccessor.normalOfset
    var texcoordOfset = cGeometry.faceAccessor.texcoordOfset

    var vertexData = cGeometry.vertices
    var texCoordData = cGeometry.texcoords
    var normalData = cGeometry.normals
    var faces = cGeometry.triangles

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

            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi0, ni0, ti0,
                                        vertWeightsData, boneIDsData, skeleton, skinController, vertexesHash, tangent.x, tangent.y, tangent.z, true))
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi1, ni1, ti1,
                                        vertWeightsData, boneIDsData, skeleton, skinController, vertexesHash, tangent.x, tangent.y, tangent.z, true))
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi2, ni2, ti2,
                                        vertWeightsData, boneIDsData, skeleton, skinController, vertexesHash, tangent.x, tangent.y, tangent.z, true))
        else:
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi0, ni0, ti0,
                                        vertWeightsData, boneIDsData, skeleton, skinController, vertexesHash))
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi1, ni1, ti1,
                                        vertWeightsData, boneIDsData, skeleton, skinController, vertexesHash))
            indexData.add(mergeIndexes(m, vertexData, texCoordData, normalData, vertexAttrData, vi2, ni2, ti2,
                                        vertWeightsData, boneIDsData, skeleton, skinController, vertexesHash))

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

proc getSkinControllerByName(colladaScene: ColladaScene, name: string): ColladaSkinController =
    if colladaScene.skinControllers.isNil:
        return nil

    for sc in colladaScene.skinControllers:
        if sc.id.contains(name):
            return sc

proc getAnimationSourceByName(anim: ColladaAnimation, name: string): ColladaSource =
    for source in anim.sources:
        if source.id.contains(name):
            return source

    for animation in anim.children:
        return animation.getAnimationSourceByName(name)

proc getSkinSourceByName(skin: ColladaSkinController, name: string): ColladaSource =
    for source in skin.sources:
        if source.id.contains(name):
            return source

proc getNodeByName(cnode: ColladaNode, name: string): ColladaNode =
    if cnode.name.contains(name):
        return cnode

    for child in cnode.children:
        return child.getNodeByName(name)

proc setupFromColladaNode(cn: ColladaNode, colladaScene: ColladaScene, resourcePath: string): Node

proc loadBones(bone: var Bone, animDuration: var float, node: var Node,
                cn: ColladaNode, colladaScene: ColladaScene,
                skinController: ColladaSkinController, boneID: var int, resourcePath: string) =
    bone = newBone()
    bone.name = cn.name
    bone.startMatrix = parseMatrix4(cn.matrix)
    bone.startMatrix.transpose()
    bone.id = boneID
    boneID.inc()

    var invMat = skinController.boneInvMatrix(bone.name)
    if not invMat.isNil:
        bone.invMatrix = parseMatrix4( skinController.boneInvMatrix(bone.name) )
        bone.invMatrix.transpose()
        # echo "bone name  ", bone.name,  "inverted matrix  ", bone.invMatrix
    else:
        bone.invMatrix = bone.startMatrix.inversed()

    var bindShapeMatrix = parseMatrix4(skinController.bindShapeMatrix)
    bindShapeMatrix.transpose()

    bone.invMatrix = bone.invMatrix * bindShapeMatrix

    var sourceMatrix: ColladaSource
    var sourceTime: ColladaSource
    for anim in colladaScene.animations:
        let sm = anim.getAnimationSourceByName(bone.name & "-Matrix-animation-output-transform")
        if not sm.isNil:
            sourceMatrix = sm

        let st = anim.getAnimationSourceByName(bone.name & "-Matrix-animation-input")
        if not st.isNil:
            sourceTime = st

    if not sourceMatrix.isNil:
        var animTrack = newAnimationTrack()
        var matData = newSeq[float32](16)
        bone.animTrack = animTrack

        for i in 0 ..< int(sourceMatrix.dataFloat.len / 16):
            for j in 0 .. 15:
                matData[j] = sourceMatrix.dataFloat[16*i + j]

            var frame = AnimationFrame.new()
            frame.matrix = parseMatrix4(matData)
            frame.matrix.transpose()
            frame.matrix = frame.matrix
            frame.time = sourceTime.dataFloat[i]
            animTrack.frames.add(frame)

            if animDuration < frame.time:
                animDuration = frame.time

    for joint in cn.children:
        if joint.kind != NodeKind.Joint:
            let newNode = setupFromColladaNode(joint, colladaScene, resourcePath)
            node.addChild(newNode)
            bone.atachedNodes.add(newNode)
            continue

        var b: Bone
        b.loadBones(animDuration, node, joint, colladaScene, skinController, boneID, resourcePath)
        if not b.isNil:
            bone.children.add(b)

proc setupNodeFromCollada(node: var Node, cn: ColladaNode, colladaScene: ColladaScene, resourcePath: string) =
    if cn.matrix != nil:
        var modelMatrix = parseMatrix4(cn.matrix)

        var translation: Vector3
        var scale: Vector3
        var rotation: Vector4

        # collada store matrixes in DX format, in GL we need transposed
        modelMatrix.transpose()
        if modelMatrix.tryGetTranslationFromModel(translation) and modelMatrix.tryGetScaleRotationFromModel(scale, rotation):
            node.scale = scale
            node.position = translation
            node.rotation = newQuaternion(rotation[0], rotation[1], rotation[2], rotation[3])
    else:
        if cn.scale != nil:
            let scale = parseArray3(cn.scale)
            node.scale = newVector3(scale[0], scale[1], scale[2])

        if cn.translation != nil:
            let translation = parseArray3(cn.translation)
            node.position = newVector3(translation[0], translation[1], translation[2])

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

        node.rotation = finalRotation

    let skinController = colladaScene.getSkinControllerByName(node.name & "Controller")
    if not skinController.isNil:
        let skinSource = skinController.getSkinSourceByName(node.name & "Controller-Joints")
        let rootBoneName = skinSource.dataName[0]
        let rootBoneColladaNode = getNodeByName(colladaScene.rootNode, rootBoneName)

        var bones: Bone
        var animDuration = 0.0
        var boneID = 0
        bones.loadBones(animDuration, node, rootBoneColladaNode, colladaScene, skinController, boneID, resourcePath)

        if not bones.isNil:
            let nodeMesh = node.getComponent(MeshComponent)
            nodeMesh.skeleton = newSkeleton()
            nodeMesh.skeleton.setBones(bones)
            nodeMesh.skeleton.animDuration = animDuration

proc setupMaterialFromCollada(nodeMesh: var MeshComponent, cm: ColladaMaterial, colladaScene: ColladaScene, resourcePath: string) =
    var transparency = cm.transparency
    if transparency < 1.0:
        nodeMesh.material.blendEnable = true
    nodeMesh.material.emission = newColor(cm.emission[0], cm.emission[1], cm.emission[2], cm.emission[3])
    nodeMesh.material.ambient = newColor(cm.ambient[0], cm.ambient[1], cm.ambient[2], cm.ambient[3])
    nodeMesh.material.diffuse = newColor(cm.diffuse[0], cm.diffuse[1], cm.diffuse[2], cm.diffuse[3])
    nodeMesh.material.specular = newColor(cm.specular[0], cm.specular[1], cm.specular[2], cm.specular[3])
    if cm.shininess > 1.0:
        nodeMesh.material.shininess = cm.shininess
    else:
        nodeMesh.material.shininess = 1.0

    #TODO
    # reflective*: Vector4
    # transparent*: Vector4
    # transparentTextureName*: string
    # add other material texture
    # childMesh.material.falloffTexture = imageWithResource("")

    if cm.diffuseTextureName != nil:
        var texName = colladaScene.getTextureLocationByName(cm.diffuseTextureName)
        if texName != nil:
            nodeMesh.material.albedoTexture = imageWithResource(texName.toAbsolutePath(resourcePath))
            nodeMesh.material.diffuse = newColor(1.0, 1.0, 1.0, 1.0)

    if cm.reflectiveTextureName != nil:
        var texName = colladaScene.getTextureLocationByName(cm.reflectiveTextureName)
        if texName != nil:
            nodeMesh.material.reflectionTexture = imageWithResource(texName.toAbsolutePath(resourcePath))
            nodeMesh.material.reflectionPercent = cm.reflectivity

    if cm.specularTextureName != nil:
        var texName = colladaScene.getTextureLocationByName(cm.specularTextureName)
        if texName != nil:
            nodeMesh.material.specularTexture = imageWithResource(texName.toAbsolutePath(resourcePath))
    # normalmap tex seted manually in dae file
    if cm.normalmapTextureName != nil:
        var texName = colladaScene.getTextureLocationByName(cm.normalmapTextureName)
        if texName != nil:
            nodeMesh.material.normalTexture = imageWithResource(texName.toAbsolutePath(resourcePath))

proc setupFromColladaNode(cn: ColladaNode, colladaScene: ColladaScene, resourcePath: string): Node =
    var node = newNode(cn.name)
    var materialInited = false
    var geometryInited = false
    var childColladaMaterial: ColladaMaterial
    var childColladaGeometry: ColladaGeometry
    var nodeMesh: MeshComponent

    for geom in colladaScene.childNodesGeometry:
        if geom.name.contains(cn.name):
            childColladaGeometry = geom
            geometryInited = true
            nodeMesh = node.component(MeshComponent)

    node.setupNodeFromCollada(cn, colladaScene, resourcePath)

    if cn.material != nil:
        for mat in colladaScene.childNodesMaterial:
            if mat.name.contains(cn.material) or cn.material.contains(mat.name):
                childColladaMaterial = mat
                materialInited = true

    if materialInited and not nodeMesh.isNil:
        nodeMesh.setupMaterialFromCollada(childColladaMaterial, colladaScene, resourcePath)

    if geometryInited:
        nodeMesh.resourceName = childColladaGeometry.name

        let bNeedComputeTangentData = if nodeMesh.material.normalTexture.isNil(): false else: true
        var vertexAttrData = newSeq[GLfloat]()
        var indexData = newSeq[GLushort]()
        var vertWeightsData = newSeq[GLfloat]()
        var boneIDsData = newSeq[GLfloat]()
        let skinController = colladaScene.getSkinControllerByName(node.name & "Controller")

        nodeMesh.prepareVBO(childColladaGeometry, vertexAttrData, indexData, vertWeightsData, boneIDsData, nodeMesh.skeleton, skinController, bNeedComputeTangentData)
        nodeMesh.vboData.vertInfo = newVertexInfoWithVertexData(childColladaGeometry.vertices.len, childColladaGeometry.texcoords.len, childColladaGeometry.normals.len, if bNeedComputeTangentData: 3 else: 0)
        nodeMesh.createVBO(indexData, vertexAttrData)

        if not nodeMesh.skeleton.isNil:
            nodeMesh.currMesh = vertexAttrData
            nodeMesh.initMesh = vertexAttrData
            nodeMesh.vertexWeights = vertWeightsData
            nodeMesh.boneIDs = boneIDsData

    result = node
    for it in cn.children:
        if it.kind != NodeKind.Joint:
            result.addChild(setupFromColladaNode(it, colladaScene, resourcePath))

proc loadColladaFromStream(s: Stream): ColladaScene =
    var loader: ColladaLoader
    result = loader.load(s)
    s.close()

# --------------- TODO ------
proc loadSceneAsync*(resourcePath: string, handler: proc(n: Node3D)) =
    sharedAssetManager().getAssetAtPath(resourcePath) do(colladaScene: ColladaScene, err: string):
        let res = setupFromColladaNode(colladaScene.rootNode, colladaScene, resourcePath)
        for anim in colladaScene.animations:
            discard animationWithCollada(res, anim)
        handler(res)

registerAssetLoader(["dae"]) do(url: string, callback: proc(s: ColladaScene)):
    openStreamForUrl(url) do(s: Stream, err: string):
        let colladaScene = loadColladaFromStream(s)
        callback(colladaScene)
