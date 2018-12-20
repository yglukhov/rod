import json

import nimx / [ types, matrixes, property_visitor ]
import rod / [ node, rod_types, component, tools/serializer ]
import rod.component.sprite
import rod / utils / [property_desc, serialization_codegen ]

type CompRef* = ref object of Component
    size*: Size
    path: string
    refNode: Node

CompRef.properties:
    size
    path

proc setSize(n: Node, sz: Size) =
    for c in n.components:
        if c of Sprite:
            let s = Sprite(c)
            s.size = sz
    for c in n.children:
        c.setSize(sz)

proc awake(c: CompRef) =
    let n = newNodeWithResource(c.path)
    n.setSize(c.size)
    c.node.addChild(n)
    c.refNode = n

proc setSize*(c: CompRef, s: Size)=
    if not c.refNode.isNil:
        c.refNode.setSize(s)

method deserialize*(s: CompRef, j: JsonNode, serializer: Serializer) =
    let v = j{"size"}
    if not v.isNil:
        s.size = newSize(v[0].getFloat(), v[1].getFloat())
    s.path = j["path"].str
    s.awake()

genSerializationCodeForComponent(CompRef)

method getBBox*(s: CompRef): BBox =
    result.minPoint = newVector3(0.0, 0.0, 0.0)
    result.maxPoint = newVector3(s.size.width, s.size.height, 0.0)

method visitProperties*(c: CompRef, p: var PropertyVisitor) =
    p.visitProperty("size", c.size)
    c.setSize(c.size)

method serialize*(c: CompRef, s: Serializer): JsonNode =
    result = newJObject()
    result.add("size", s.getValue(c.size))
    result.add("path", s.getValue(c.path))

registerComponent(CompRef)
