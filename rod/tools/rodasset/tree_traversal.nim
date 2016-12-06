import json

iterator allNodes*(n: JsonNode): JsonNode =
    var stack = @[n]
    while stack.len > 0:
        let n = stack.pop()
        yield n
        let children = n{"children"}
        if not children.isNil:
            stack.add(children.elems)

iterator componentNodes*(n: JsonNode): tuple[typ: string, node: JsonNode] =
    let components = n{"components"}
    if not components.isNil:
        var comps = newSeq[(string, JsonNode)]()
        if components.kind == JObject:
            for k, v in components:
                comps.add((k, v))
        elif components.kind == JArray:
            for c in components.elems:
                comps.add((c["_c"].str, c))
        for c in comps:
            yield c

iterator allComponentNodesOfType*(n: JsonNode, typ: string): (JsonNode, JsonNode) =
    var comps = newSeq[JsonNode]()
    for n in n.allNodes:
        for c in n.componentNodes:
            if c.typ == typ:
                yield(n, c.node)

iterator allSpriteNodes*(n: JsonNode): (JsonNode, JsonNode) =
    for n, c in allComponentNodesOfType(n, "Sprite"): yield(n, c)

iterator allMeshComponentNodes*(n: JsonNode): (JsonNode, JsonNode) =
    for n, c in allComponentNodesOfType(n, "MeshComponent"): yield(n, c)
