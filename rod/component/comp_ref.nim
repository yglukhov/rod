import json

import nimx / [ types, matrixes, property_visitor, resource ]
import rod / [ node, rod_types, component, tools/serializer ]
import rod.component.sprite

type CompRef* = ref object of Component
    size*: Size
    path: string

proc setSize(n: Node, sz: Size) =
    for c in n.components:
        if c of Sprite:
            let s = Sprite(c)
            s.size = sz
    for c in n.children:
        c.setSize(sz)

method deserialize*(s: CompRef, j: JsonNode, serializer: Serializer) =
    let v = j{"size"}
    if not v.isNil:
        s.size = newSize(v[0].getFNum(), v[1].getFNum())
    s.path = j["path"].str

    pushParentResource("")
    let n = newNodeWithResource(s.path & ".json")
    popParentResource()
    n.setSize(s.size)

    s.node.addChild(n)

method getBBox*(s: CompRef): BBox =
    result.minPoint = newVector3(0.0, 0.0, 0.01)
    result.maxPoint = newVector3(s.size.width, s.size.height, 0.0)

method visitProperties*(c: CompRef, p: var PropertyVisitor) =
    p.visitProperty("size", c.size)

method serialize*(c: CompRef, s: Serializer): JsonNode =
    result = newJObject()
    result.add("size", s.getValue(c.size))
    result.add("path", s.getValue(c.path))

registerComponent(CompRef)
