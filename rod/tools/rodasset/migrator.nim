import json, os, strutils

import tree_traversal

proc hasComponentOfType(n: JsonNode, typ: string): bool =
    for c in n.componentNodes:
        if c.typ == typ: return true

proc convertDictComponentsToArray*(node: JsonNode) =
    let comps = node{"components"}
    if not comps.isNil and comps.kind == JObject:
        let newComps = newJArray()
        for k, v in comps:
            v["_c"] = %k
            newComps.add(v)
        node["components"] = newComps

proc removeComponentsOfType(n: JsonNode, typ: string) =
    var i = 0
    let comps = n["components"]
    while i < comps.len:
        if comps[i]["_c"].str == typ:
            comps.elems.del(i)
        else:
            inc i

proc removeAnimationsForProperties(composition: JsonNode, nodeName, propertyName: string) =
    let anims = composition{"animations"}
    let fqpn = nodeName & "." & propertyName
    if not anims.isNil:
        for animName, anim in anims:
            if fqpn in anim:
                echo "Deleting ", fqpn, " from animation ", animName
                anim.delete(fqpn)

proc fixupChannelLevelsWithDrawablesOnTheSameNode(composition, n: JsonNode) =
    if n.hasComponentOfType("ChannelLevels") and (n.hasComponentOfType("Sprite") or n.hasComponentOfType("Text") or n.hasComponentOfType("Solid")):
        let children = n{"children"}
        if not children.isNil and children.len > 0:
            raise newException(Exception, "Found Channel levels in node with drawable and children")
        n.removeComponentsOfType("ChannelLevels")
        let name = n{"name"}
        if not name.isNil:
            echo "removing ChannelLevels from ", name
            for p in ["inWhite", "inBlack", "inGamma", "outWhite", "outBlack", "redInWhite",
                    "redInBlack", "redInGamma", "redOutWhite", "redOutBlack", "greenInWhite",
                    "greenInBlack", "greenInGamma", "greenOutWhite", "greenOutBlack", "blueInWhite",
                    "blueInBlack", "blueInGamma", "blueOutWhite", "blueOutBlack"]:

                composition.removeAnimationsForProperties(name.str, p)

proc upgradeTo1(composition: JsonNode): JsonNode =
    for n in composition.allNodes:
        n.convertDictComponentsToArray()
        fixupChannelLevelsWithDrawablesOnTheSameNode(composition, n)

const upgraders = {
    1: upgradeTo1
}

proc upgradeAssetBundle*(path: string) =
    for f in walkDirRec(path):
        if f.endsWith(".json"):
            echo "processing ", f
            try:
                var j = parseJson(readFile(f))
                for upgrader in upgraders:
                    let v = j{"version"}.getNum().int
                    if v < upgrader[0]:
                        let newV = upgrader[1](j)
                        if not newV.isNil:
                            j = newV
                        j["version"] = %upgrader[0]
                writeFile(f, j.pretty().replace(" \l", "\l"))
            except:
                echo "ERROR: ", getCurrentExceptionMsg()
                echo getCurrentException().getStackTrace()
