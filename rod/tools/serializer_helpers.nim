import json

import nimx.image
import nimx.types
import nimx.matrixes

import rod.rod_types
import rod.node

proc getSerializedValue*(j: JsonNode, name: string, val: var float32) =
    let jN = j{name}
    if not jN.isNil:
        val = jN.getFnum()

proc getSerializedValue*(j: JsonNode, name: string, val: var float) =
    let jN = j{name}
    if not jN.isNil:
        val = jN.getFnum()

proc getSerializedValue*(j: JsonNode, name: string, val: var Vector3) =
    let jN = j{name}
    if not jN.isNil:
        val = newVector3(jN[0].getFnum(), jN[1].getFnum(), jN[2].getFnum())

proc getSerializedValue*(j: JsonNode, name: string, val: var Image) =
    let jN = j{name}
    if not jN.isNil:
        val = imageWithResource(jN.getStr())

proc getSerializedValue*(j: JsonNode, name: string, val: var bool) =
    let jN = j{name}
    if not jN.isNil:
        val = jN.getBVal()

proc getSerializedValue*(j: JsonNode, name: string, val: var Node) =
    let jN = j{name}
    if not jN.isNil and jN.getStr().len > 0:
        val = newNode(jN.getStr())