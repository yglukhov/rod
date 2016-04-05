import tables
import typetraits
import json
import strutils
import math

import nimx.context
import nimx.types
import nimx.resource
import nimx.animation
import nimx.image
import nimx.portable_gl
import nimx.view

import quaternion
import property_visitor

import rod_types
export Node

proc sceneView*(n: Node): SceneView = n.mSceneView

import rod.component

proc newNode*(name: string = nil): Node =
    result.new()
    result.scale = newVector3(1, 1, 1)
    result.rotation = newQuaternion()
    result.children = @[]
    result.name = name
    result.alpha = 1.0

proc createComponentForNode(n: Node, name: string): Component =
    result = createComponent(name)
    result.node = n
    if not n.mSceneView.isNil:
        result.componentNodeWasAddedToSceneView()

proc component*(n: Node, name: string): Component =
    if n.components.isNil:
        n.components = newTable[string, Component]()
        result = createComponentForNode(n, name)
        n.components[name] = result
    else:
        result = n.components.getOrDefault(name)
        if result.isNil:
            result = createComponentForNode(n, name)
            n.components[name] = result

proc component*(n: Node, T: typedesc[Component]): T =
    type TT = T
    result = TT(n.component(T.name))

proc componentIfAvailable*(n: Node, name: string): Component =
    if not n.components.isNil:
        result = n.components.getOrDefault(name)

proc componentIfAvailable*(n: Node, T: typedesc[Component]): T =
    type TT = T
    result = TT(n.componentIfAvailable(T.name))

proc setComponent*(n: Node, name: string, c: Component) =
    if n.components.isNil:
        n.components = newTable[string, Component]()
    n.components[name] = c

proc removeComponent*(n: Node, name: string) =
    if not n.components.isNil:
        let c = n.components.getOrDefault(name)
        if not c.isNil:
            c.componentNodeWillBeRemovedFromSceneView()
            n.components.del(name)

proc removeComponent*(n: Node, T: typedesc[Component]) = n.removeComponent(T.name)

proc update(n: Node) =
    if not n.components.isNil:
        for k, v in n.components:
            v.update()

proc recursiveUpdate*(n: Node) =
    n.update()
    for c in n.children: c.recursiveUpdate()

proc getTransform*(n: Node, mat: var Matrix4) =
    mat.translate(n.translation)
    mat.multiply(n.rotation.toMatrix4(), mat)
    mat.scale(n.scale)

# Transformations
proc transform*(n: Node): Matrix4 =
    result.loadIdentity()
    n.getTransform(result)

proc recursiveDraw*(n: Node) =
    if n.alpha < 0.0000001: return
    let c = currentContext()
    var tr = c.transform
    let oldAlpha = c.alpha
    c.alpha *= n.alpha
    n.getTransform(tr)
    c.withTransform tr:
        var hasPosteffectComponent = false
        if not n.components.isNil:
            for v in values(n.components):
                v.draw()
                hasPosteffectComponent = hasPosteffectComponent or v.isPosteffectComponent()
        if not hasPosteffectComponent:
            for c in n.children: c.recursiveDraw()
    c.alpha = oldAlpha

proc nodeWillBeRemovedFromSceneView*(n: Node) =
    if not n.components.isNil:
        for c in n.components.values: c.componentNodeWillBeRemovedFromSceneView()
    if not n.children.isNil:
        for c in n.children: c.nodeWillBeRemovedFromSceneView()
    n.mSceneView = nil

proc nodeWasAddedToSceneView*(n: Node, v: SceneView) =
    n.mSceneView = v
    if not n.components.isNil:
        for c in n.components.values: c.componentNodeWasAddedToSceneView()
    if not n.children.isNil:
        for c in n.children: c.nodeWasAddedToSceneView(v)

proc removeChild(n, child: Node) =
    for i, c in n.children:
        if c == child:
            n.children.delete(i)
            break

proc removeAllChildren*(n: Node) =
    for c in n.children:
        if not c.mSceneView.isNil:
            c.nodeWillBeRemovedFromSceneView()
        c.parent = nil
    n.children.setLen(0)

proc removeFromParent*(n: Node) =
    if not n.parent.isNil:
        if not n.mSceneView.isNil:
            n.nodeWillBeRemovedFromSceneView()

        n.parent.removeChild(n)
        n.parent = nil

proc addChild*(n, c: Node) =
    c.removeFromParent()
    n.children.safeAdd(c)
    c.parent = n
    if not n.mSceneView.isNil:
        c.nodeWasAddedToSceneView(n.mSceneView)

proc newChild*(n: Node, childName: string = nil): Node =
    result = newNode(childName)
    n.addChild(result)

proc findNode*(n: Node, p: proc(n: Node): bool): Node =
    if p(n):
        result = n
    else:
        for c in n.children:
            result = c.findNode(p)
            if not result.isNil: break

proc findNode*(n: Node, name: string): Node =
    n.findNode proc(n: Node): bool =
        n.name == name

proc childNamed*(n: Node, name: string): Node =
    for c in n.children:
        if c.name == name: return c

proc translationFromMatrix(m: Matrix4): Vector3 = [m[12], m[13], m[14]]

proc worldTransform*(n: Node): Matrix4 =
    if n.parent.isNil:
        result = n.transform
    else:
        let w = n.parent.worldTransform
        w.multiply(n.transform, result)

proc localToWorld*(n: Node, p: Vector3): Vector3 =
    result = n.worldTransform * p

proc worldToLocal*(n: Node, p: Vector3): Vector3 =
    n.worldTransform.inversed() * p

proc tryWorldToLocal*(n: Node, p: Vector3, res: var Vector3): bool =
    var m : Matrix4
    if n.worldTransform.tryInverse(m):
        res = m * p
        result = true

proc worldPos*(n: Node): Vector3 =
    result = n.localToWorld(newVector3())

proc `worldPos=`(n: Node, p: Vector3) =
    n.translation = n.parent.worldToLocal(p)

proc visitProperties*(n: Node, p: var PropertyVisitor) =
    p.visitProperty("name", n.name)
    p.visitProperty("translation", n.translation)
    p.visitProperty("worldPos", n.worldPos)
    p.visitProperty("scale", n.scale)
    p.visitProperty("rotation", n.rotation)
    p.visitProperty("alpha", n.alpha)

    p.visitProperty("tX", n.translation.x, { pfAnimatable })
    p.visitProperty("tY", n.translation.y, { pfAnimatable })
    p.visitProperty("tZ", n.translation.z, { pfAnimatable })
    p.visitProperty("sX", n.scale.x, { pfAnimatable })
    p.visitProperty("sY", n.scale.y, { pfAnimatable })
    p.visitProperty("sZ", n.scale.z, { pfAnimatable })

proc reparentTo*(n, newParent: Node) =
    # Change parent of a node preserving its world transform
    let oldWorldTransform = n.worldTransform
    newParent.addChild(n)
    let newTransform = newParent.worldTransform.inversed() * oldWorldTransform
    n.translation = translationFromMatrix(newTransform)

proc animationNamed*(n: Node, name: string, preserveHandlers: bool = false): Animation =
    if not n.animations.isNil:
        result = n.animations.getOrDefault(name)
        if not result.isNil and not preserveHandlers: result.removeHandlers()

proc registerAnimation*(n: Node, name: string, a: Animation) =
    if n.animations.isNil:
        n.animations = newTable[string, Animation]()
    n.animations[name] = a

# Serialization
proc newNodeFromJson*(j: JsonNode): Node
proc deserialize*(n: Node, j: JsonNode)

proc loadComposition*(n: Node, resourceName: string) =
    loadJsonResourceAsync resourceName, proc(j: JsonNode) =
        pushParentResource(resourceName)
        n.deserialize(j)
        popParentResource()

import ae_animation

proc deserialize*(n: Node, j: JsonNode) =
    if n.name.isNil:
        n.name = j["name"].getStr(nil)
    var v = j{"translation"}
    if not v.isNil:
        n.translation = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    v = j{"scale"}
    if not v.isNil:
        n.scale = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    v = j{"rotation"}
    if not v.isNil:
        n.rotation = newQuaternion(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())
    v = j{"alpha"}
    if not v.isNil:
        n.alpha = v.getFNum()
    v = j{"children"}
    if not v.isNil:
        for i in 0 ..< v.len:
            n.addChild(newNodeFromJson(v[i]))
    v = j{"components"}
    if not v.isNil:
        for k, c in v:
            let comp = n.component(k)
            comp.deserialize(c)
    let animations = j{"animations"}

    if not animations.isNil and animations.len > 0:
        n.animations = newTable[string, Animation]()
        for k, v in animations:
            n.animations[k] = animationWithAEJson(n, v)

    let compositionRef = j{"compositionRef"}.getStr(nil)
    if not compositionRef.isNil and not n.name.endsWith(".placeholder"):
        n.loadComposition(compositionRef)

proc newNodeFromJson*(j: JsonNode): Node =
    result = newNode()
    result.deserialize(j)

proc newNodeWithResource*(name: string): Node =
    result = newNode()
    result.loadComposition(name)

proc newNodeWithCompositionName*(name: string): Node {.deprecated.} =
    result = newNode()
    result.loadComposition("compositions/" & name & ".json")

proc getDepth*(n: Node): int =
    result = 0

    var p = n.parent
    while not p.isNil:
        inc result
        p = p.parent

proc getTreeDistance*(x, y: Node): int =
    var xLevel = x.getDepth()
    var yLevel = y.getDepth()
    var px = x
    var py = y

    while xLevel > yLevel:
        dec xLevel
        px = px.parent
    while yLevel > xLevel:
        dec yLevel
        py = py.parent

    assert(px != py)
    var cx, cy : Node
    while px != py:
        cx = px
        cy = py
        px = px.parent
        py = py.parent

    assert(not cx.isNil and not cy.isNil)

    let ix = px.children.find(cx)
    let iy = px.children.find(cy)

    result = iy - ix

# Debugging
proc recursiveChildrenCount*(n: Node): int =
    result = n.children.len
    for c in n.children:
        result += c.recursiveChildrenCount
