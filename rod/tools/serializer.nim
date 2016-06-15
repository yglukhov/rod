import json
import tables
import typetraits
import streams
when not defined(js) and not defined(android) and not defined(ios):
    import os

import nimx.image
import nimx.types
import nimx.pathutils
import nimx.matrixes

import rod.rod_types
import rod.component
import rod.component.material
import rod.component.sprite
import rod.component.light
import rod.component.text_component
import rod.component.mesh_component
import rod.component.particle_system
import rod.component.particle_helpers
import rod.component.animation.skeleton

type Serializer* = ref object
    savePath*: string

proc vectorToJNode[T](vec: T): JsonNode =
    result = newJArray()
    for k, v in vec:
        result.add(%v)

proc `%`*(n: Node): JsonNode =
    if not n.isNil:
        result = newJString(n.name)
    else:
        result = newJString("")

proc `%`*[I: static[int], T](vec: TVector[I, T]): JsonNode =
    result = vectorToJNode(vec)

proc `%`*(v: Size): JsonNode =
    result = vectorToJNode(newVector2(v.width, v.height))

proc `%`*(v: Color): JsonNode =
    result = newJArray()
    for k, val in v.fieldPairs:
        result.add( %val )

proc `%`*[T](elements: openArray[T]): JsonNode =
    result = newJArray()
    for elem in elements:
        result.add(%elem)

proc colorToJNode(color:Color): JsonNode =
    result = newJArray()
    for k, v in color.fieldPairs:
        result.add( %v )

proc getRelativeResourcePath(s: Serializer, path: string): string =
    var resourcePath = path
    when not defined(js) and not defined(android) and not defined(ios):
        resourcePath = parentDir(s.savePath)

    result = relativePathToPath(resourcePath, path)
    echo "save path = ", resourcePath, "  relative = ", result

method getComponentData(s: Serializer, c: Component): JsonNode {.base.} =
    result = newJObject()

method getComponentData(s: Serializer, c: Text): JsonNode =
    result = newJObject()
    result.add("text", %c.text)
    result.add("color", colorToJNode(c.color))
    result.add("shadowX", %c.shadowX)
    result.add("shadowY", %c.shadowY)
    result.add("shadowColor", colorToJNode(c.shadowColor))
    result.add("Tracking Amount", %c.trackingAmount)

method getComponentData(s: Serializer, c: Sprite): JsonNode =
    result = newJObject()
    result.add("currentFrame", %c.currentFrame)

    var imagesNode = newJArray()
    result.add("fileNames", imagesNode)
    for img in c.images:
        imagesNode.add( %s.getRelativeResourcePath(img.filePath()) )

method getComponentData(s: Serializer, c: LightSource): JsonNode =
    result = newJObject()
    result.add("ambient", %c.lightAmbient)
    result.add("diffuse", %c.lightDiffuse)
    result.add("specular", %c.lightSpecular)
    result.add("constant", %c.lightConstant)
    result.add("linear", %c.lightLinear)
    result.add("quadratic", %c.lightQuadratic)
    result.add("is_precomp_attenuation", %c.lightAttenuationInited)
    result.add("attenuation", %c.lightAttenuation)
    result.add("color", %c.lightColor)

method getComponentData(s: Serializer, c: ParticleSystem): JsonNode =
    result = newJObject()
    result.add("duration", %c.duration)
    result.add("isLooped", %c.isLooped)
    result.add("isPlayed", %c.isPlayed)
    result.add("birthRate", %c.birthRate)
    result.add("lifetime", %c.lifetime)
    result.add("startVelocity", %c.startVelocity)
    result.add("randVelocityFrom", %c.randVelocityFrom)
    result.add("randVelocityTo", %c.randVelocityTo)
    result.add("is3dRotation", %c.is3dRotation)
    result.add("randRotVelocityFrom", %c.randRotVelocityFrom)
    result.add("randRotVelocityTo", %c.randRotVelocityTo)
    result.add("startScale", %c.startScale)
    result.add("dstScale", %c.dstScale)
    result.add("randScaleFrom", %c.randScaleFrom)
    result.add("randScaleTo", %c.randScaleTo)
    result.add("startColor", %c.startColor)
    result.add("dstColor", %c.dstColor)
    result.add("isBlendAdd", %c.isBlendAdd)
    result.add("gravity", %c.gravity)

    result.add("scaleMode", %c.scaleMode.ord)
    result.add("colorMode", %c.colorMode.ord)
    result.add("scaleSeq", %c.scaleSeq)
    result.add("colorSeq", %c.colorSeq)

    if c.texture.filePath().len > 0:
        result.add("texture", %s.getRelativeResourcePath(c.texture.filePath()))
        result.add("isTextureAnimated", %c.isTextureAnimated)
        result.add("texSize", %c.frameSize)
        result.add("animColumns", %c.animColumns)
        result.add("framesCount", %c.framesCount)
        result.add("fps", %c.fps)

    result.add("attractorNode", %c.attractorNode)
    result.add("genShapeNode", %c.genShapeNode)

    result.add("isMove", %c.isMove)
    result.add("amplitude", %c.amplitude)
    result.add("frequency", %c.frequency)
    result.add("distance", %c.distance)
    result.add("speed", %c.speed)

method getComponentData(s: Serializer, c: ConePSGenShape): JsonNode =
    result = newJObject()
    result.add("angle", %c.angle)
    result.add("radius", %c.radius)
    result.add("is2D", %c.is2D)

method getComponentData(s: Serializer, c: SpherePSGenShape): JsonNode =
    result = newJObject()
    result.add("radius", %c.radius)
    result.add("isRandPos", %c.isRandPos)
    result.add("isRandDir", %c.isRandDir)
    result.add("is2D", %c.is2D)

method getComponentData(s: Serializer, c: BoxPSGenShape): JsonNode =
    result = newJObject()
    result.add("dimension", %c.dimension)
    result.add("is2D", %c.is2D)

method getComponentData(s: Serializer, c: WavePSAttractor): JsonNode =
    result = newJObject()
    result.add("forceValue", %c.forceValue)
    result.add("frequence", %c.frequence)


proc getAnimationTrackData(s: Serializer, track: AnimationTrack): JsonNode =
    result = newJArray()
    for frame in track.frames:
        var frameNode = newJObject()
        frameNode.add("time", %frame.time)
        frameNode.add("matrix", %frame.matrix)
        result.add(frameNode)

proc getBonesData(s: Serializer, bone: Bone): JsonNode =
    result = newJObject()
    result.add("name", %bone.name)
    result.add("id", %bone.id)
    result.add("startMatrix", %bone.startMatrix)
    result.add("invMatrix", %bone.invMatrix)
    result.add("animTrack", s.getAnimationTrackData(bone.animTrack))

    var childrenNode = newJArray()
    result.add("children", childrenNode)
    for child in bone.children:
        childrenNode.add( s.getBonesData(child) )

proc getSkeletonData(s: Serializer, skeleton: Skeleton): JsonNode =
    result = newJObject()
    result.add("animDuration", %skeleton.animDuration)
    result.add("rootBone", s.getBonesData(skeleton.rootBone))

method getComponentData(s: Serializer, c: MeshComponent): JsonNode =
    result = newJObject()

    result.add("emission", colorToJNode(c.material.emission))
    result.add("ambient", colorToJNode(c.material.ambient))
    result.add("diffuse", colorToJNode(c.material.diffuse))
    result.add("specular", colorToJNode(c.material.specular))
    result.add("shininess", %c.material.shininess)
    result.add("rim_density", %c.material.rim_density)

    result.add("culling", %c.material.bEnableBackfaceCulling)
    result.add("light", %c.material.isLightReceiver)
    result.add("blend", %c.material.blendEnable)
    result.add("depth_test", %c.material.depthEnable)
    result.add("wireframe", %c.material.isWireframe)
    result.add("RIM", %c.material.isRIM)
    result.add("rimColor", colorToJNode(c.material.rimColor))

    result.add("sRGB_normal", %c.material.isNormalSRGB)

    result.add("matcapPercent", %c.material.matcapPercent)
    result.add("matcapInterpolatePercent", %c.material.matcapInterpolatePercent)
    result.add("albedoPercent", %c.material.albedoPercent)
    result.add("glossPercent", %c.material.glossPercent)
    result.add("specularPercent", %c.material.specularPercent)
    result.add("normalPercent", %c.material.normalPercent)
    result.add("bumpPercent", %c.material.bumpPercent)
    result.add("reflectionPercent", %c.material.reflectionPercent)
    result.add("falloffPercent", %c.material.falloffPercent)
    result.add("maskPercent", %c.material.maskPercent)

    result.add("matcapMixPercent", %c.material.matcapMixPercent)

    if not c.material.matcapTexture.isNil:
        result.add("matcapTexture",  %s.getRelativeResourcePath(c.material.matcapTexture.filePath()))
    if not c.material.matcapInterpolateTexture.isNil:
        result.add("matcapInterpolateTexture",  %s.getRelativeResourcePath(c.material.matcapInterpolateTexture.filePath()))
    if not c.material.albedoTexture.isNil:
        result.add("albedoTexture",  %s.getRelativeResourcePath(c.material.albedoTexture.filePath()))
    if not c.material.glossTexture.isNil:
        result.add("glossTexture",  %s.getRelativeResourcePath(c.material.glossTexture.filePath()))
    if not c.material.specularTexture.isNil:
        result.add("specularTexture",  %s.getRelativeResourcePath(c.material.specularTexture.filePath()))
    if not c.material.normalTexture.isNil:
        result.add("normalTexture",  %s.getRelativeResourcePath(c.material.normalTexture.filePath()))
    if not c.material.bumpTexture.isNil:
        result.add("bumpTexture",  %s.getRelativeResourcePath(c.material.bumpTexture.filePath()))
    if not c.material.reflectionTexture.isNil:
        result.add("reflectionTexture",  %s.getRelativeResourcePath(c.material.reflectionTexture.filePath()))
    if not c.material.falloffTexture.isNil:
        result.add("falloffTexture",  %s.getRelativeResourcePath(c.material.falloffTexture.filePath()))
    if not c.material.maskTexture.isNil:
        result.add("maskTexture",  %s.getRelativeResourcePath(c.material.maskTexture.filePath()))

    var data = c.getVBDataFromVRAM()

    proc needsKey(name: string): bool =
        case name
        of "vertex_coords": return c.vboData.vertInfo.numOfCoordPerVert > 0 or false
        of "tex_coords": return c.vboData.vertInfo.numOfCoordPerTexCoord > 0  or false
        of "normals": return c.vboData.vertInfo.numOfCoordPerNormal > 0  or false
        of "tangents": return c.vboData.vertInfo.numOfCoordPerTangent > 0  or false
        else: return false

    template addInfo(name: string, f: typed) =
        if needsKey(name):
            result[name] = %f(c, data)

    addInfo("vertex_coords", extractVertCoords)
    addInfo("tex_coords", extractTexCoords)
    addInfo("normals", extractNormals)
    addInfo("tangents", extractTangents)

    var ib = c.getIBDataFromVRAM()
    var ibNode = newJArray()
    result.add("indices", ibNode)
    for v in ib:
        ibNode.add(%int32(v))

    if not c.skeleton.isNil:
        result.add("skeleton", s.getSkeletonData(c.skeleton))
        result["vertexWeights"] = %c.vertexWeights
        result["boneIDs"] = %c.boneIDs

proc getNodeData(s: Serializer, n: Node): JsonNode =
    result = newJObject()
    result.add("name", %n.name)
    result.add("translation", vectorToJNode(n.translation))
    result.add("scale", vectorToJNode(n.scale))
    result.add("rotation", vectorToJNode(n.rotation))
    result.add("alpha", %n.alpha)

    if not n.components.isNil:
        var componentsNode = newJObject()
        result.add("components", componentsNode)

        for k, v in n.components:
            var jcomp: JsonNode
            jcomp = s.getComponentData( v )

            if not jcomp.isNil:
                componentsNode.add(k, jcomp)

    var childsNode = newJArray()
    result.add("children", childsNode)
    for child in n.children:
        childsNode.add( s.getNodeData(child) )


proc save*(s: Serializer, n: Node, path: string) =
    when not defined(js) and not defined(android) and not defined(ios):
        s.savePath = path
        var nd = s.getNodeData(n)
        var str = nd.pretty()

        var fs = newFileStream(path, fmWrite)
        if fs.isNil:
            echo "WARNING: Resource can not open: ", path
        else:
            fs.write(str)
            fs.close()
            echo "save at path ", path
    else:
        echo "serializer::save don't support js"

