import json
import tables
import typetraits
import streams
when not defined(js) and not defined(android) and not defined(ios):
    import os

import nimx.image
import nimx.types
import nimx.pathutils

import rod.rod_types
import rod.component
import rod.component.material
import rod.component.sprite
import rod.component.light
import rod.component.text_component
import rod.component.mesh_component

type Serializer* = ref object
    savePath*: string

proc checkComponentType(c: Component, T: typedesc): bool =
    try:
        type TT = T
        discard TT(c)
        result = true
    except:
        result = false

proc vectorToJNode[T](vec: T): JsonNode =
    result = newJArray()
    for k, v in vec:
        result.add(%v)

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

proc getComponentData(s: Serializer, c: Component): JsonNode =
    result = newJObject()

proc getComponentData(s: Serializer, c: Text): JsonNode =
    result = newJObject()
    result.add("text", %c.text)
    result.add("color", colorToJNode(c.color))
    result.add("shadowX", %c.shadowX)
    result.add("shadowY", %c.shadowY)
    result.add("shadowColor", colorToJNode(c.shadowColor))
    result.add("Tracking Amount", %c.trackingAmount)

proc getComponentData(s: Serializer, c: Sprite): JsonNode =
    result = newJObject()
    result.add("currentFrame", %c.currentFrame)

    var imagesNode = newJArray()
    result.add("fileNames", imagesNode)
    for img in c.images:
        imagesNode.add( %s.getRelativeResourcePath(img.filePath()) )


proc getComponentData(s: Serializer, c: LightSource): JsonNode =
    result = newJObject()
    result.add("ambient", %c.lightAmbient)
    result.add("diffuse", %c.lightDiffuse)
    result.add("specular", %c.lightSpecular)
    result.add("constant", %c.lightConstant)


proc getComponentData(s: Serializer, c: MeshComponent): JsonNode =
    result = newJObject()

    result.add("emission", colorToJNode(c.material.emission))
    result.add("ambient", colorToJNode(c.material.ambient))
    result.add("diffuse", colorToJNode(c.material.diffuse))
    result.add("specular", colorToJNode(c.material.specular))
    result.add("shininess", %c.material.shininess)
    result.add("reflectivity", %c.material.reflectivity)
    result.add("rim_density", %c.material.rim_density)

    result.add("culling", %c.material.bEnableBackfaceCulling)
    result.add("light", %c.material.isLightReceiver)
    result.add("blend", %c.material.blendEnable)
    result.add("depth_test", %c.material.depthEnable)
    result.add("wireframe", %c.material.isWireframe)
    result.add("RIM", %c.material.isRIM)
    result.add("sRGB_normal", %c.material.isNormalSRGB)

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
    var vc =  c.extractVertCoords(data)
    var vcNode = newJArray()
    result.add("vertex_coords", vcNode)
    for v in vc:
        vcNode.add(%v)

    var tc = c.extractTexCoords(data)
    var tcNode = newJArray()
    result.add("tex_coords", tcNode)
    for v in tc:
        tcNode.add(%v)

    var norm = c.extractNormals(data)
    var normNode = newJArray()
    result.add("normals", normNode)
    for v in norm:
        normNode.add(%v)

    var tang = c.extractTangents(data)
    var tangNode = newJArray()
    result.add("tangents", tangNode)
    for v in tang:
        tangNode.add(%v)

    var ib = c.getIBDataFromVRAM()
    var ibNode = newJArray()
    result.add("indices", ibNode)
    for v in ib:
        ibNode.add(%int32(v))


proc getNodeData(s: Serializer, n: Node): JsonNode =
    var j = newJObject()
    j.add("name", %n.name)
    j.add("translation", vectorToJNode(n.translation))
    j.add("scale", vectorToJNode(n.scale))
    j.add("rotation", vectorToJNode(n.rotation))
    j.add("alpha", %n.alpha)

    if not n.components.isNil:
        var componentsNode = newJObject()
        j.add("components", componentsNode)

        for k, v in n.components:
            var jcomp: JsonNode

            if v.checkComponentType(Sprite):
                jcomp = s.getComponentData( Sprite(v) )

            if v.checkComponentType(LightSource):
                jcomp = s.getComponentData( LightSource(v) )

            if v.checkComponentType(Text):
                jcomp = s.getComponentData( Text(v) )

            if v.checkComponentType(MeshComponent):
                jcomp = s.getComponentData( MeshComponent(v) )

            if not jcomp.isNil:
                componentsNode.add(k, jcomp)

    var childsNode = newJArray()
    j.add("children", childsNode)
    for child in n.children:
        childsNode.add( s.getNodeData(child) )

    # echo "nodeData = ", $j
    return j


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

