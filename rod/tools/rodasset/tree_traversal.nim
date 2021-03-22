import json, lists

proc append[T](lst: var DoublyLinkedList[T], elems: openarray[T]) =
    for e in elems: lst.append(e)

iterator allNodes*(n: JsonNode): JsonNode =
    var lst = initDoublyLinkedList[JsonNode]() # SinglyLinkedList would be sufficient here, but its api is currently underdeveloped
    lst.append(n)

    while not lst.head.isNil:
        let n = lst.head.value
        lst.remove(lst.head)
        yield n
        let children = n{"children"}
        if not children.isNil:
            lst.append(children.elems)

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

iterator componentNodesOfType*(n: JsonNode, typ: string): JsonNode =
    for c in n.componentNodes:
        if c.typ == typ: yield c.node

iterator allComponentNodesOfType*(n: JsonNode, typ: string): (JsonNode, JsonNode) =
    for n in n.allNodes:
        for c in n.componentNodesOfType(typ):
            yield(n, c)

iterator allSpriteNodes*(n: JsonNode): (JsonNode, JsonNode) =
    for n, c in allComponentNodesOfType(n, "Sprite"): yield(n, c)
    for n, c in allComponentNodesOfType(n, "NinePartSprite"): yield(n, c)

iterator tilemapImageLayersNodes*(n: JsonNode): (JsonNode, JsonNode) =
    for n, c in allComponentNodesOfType(n, "ImageMapLayer"): yield(n, c)

iterator tilemapNodes*(n: JsonNode): (JsonNode, JsonNode) =
    for n, c in allComponentNodesOfType(n, "TileMap"): yield(n, c)


iterator allMeshComponentNodes*(n: JsonNode): (JsonNode, JsonNode) =
    for n, c in allComponentNodesOfType(n, "MeshComponent"): yield(n, c)

iterator compositionAnimationsForNodeProperty*(compositionNode: JsonNode, nodeName, propertyName: string): (string, JsonNode) =
    let animName = nodeName & "." & propertyName
    for k, v in compositionNode["animations"]:
        let a = v{animName}
        if not a.isNil:
            yield(k, a)

proc findNode*(n: JsonNode, name: string): JsonNode =
    for c in n.allNodes:
        if c{"name"}.getStr() == name: return c

proc firstComponentOfType*(n: JsonNode, typ: string): JsonNode =
    for c in n.componentNodesOfType(typ): return c
