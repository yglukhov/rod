import json
import strutils
when not defined(js) and not defined(android) and not defined(ios):
    import os

import nimx.resource
import nimx.pathutils
import nimx.types
import rod_types

type MetaData* = ref object
    jsonNode*: JsonNode
    resourcePath*: string
    componentName*: string

proc getJsonNodeAtKeyPath*(md: MetaData, kp: string): JsonNode =
    echo "MetaData", $md.jsonNode
    var jn = md.jsonNode
    for key in kp.split("."):
        jn = jn{key}

    return jn

proc updateMetaData*(md: MetaData, keypath, name: string, jn: JsonNode) =
    var j = md.getJsonNodeAtKeyPath(keyPath)
    j{name} = jn

proc validateComponent*(md: MetaData, name:string) =
    if md.jsonNode.isNil:
        return

    var compNode = md.jsonNode{"components"}
    if compNode.isNil:
        compNode = newJObject()
        md.jsonNode.add("components", compNode)

    if not compNode.hasKey(name):
        compNode{name} = newJObject()

proc validateRecursive(md: MetaData, jn: JsonNode) =
    for k, v in jn:
        # remove not valid components
        if not v{"NodeSelector"}.isNil:
            v.delete("NodeSelector")

        pushParentResource(md.resourcePath)
        # validate image pathes (make relative)
        if not v{"image"}.isNil:
            when not defined(js) and not defined(android) and not defined(ios):
                var imgPath = pathForResource(v{"image"}.getStr())
                var resourcePath = parentDir(md.resourcePath)
                var relPath = relativePathToPath(resourcePath, imgPath)
                v.add("image", %relPath)

                echo "json path ", resourcePath
                echo "img path ", imgPath
                echo "relPath ", relPath

        if v.kind == JObject:
            md.validateRecursive(v)

        popParentResource()


proc validate*(md: MetaData) =
    md.validateRecursive(md.jsonNode)
