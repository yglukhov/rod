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
import nimx.property_visitor

import quaternion
import ray
import rod.tools.serializer

import rod_types
export Node

proc sceneView*(n: Node): SceneView = n.mSceneView
proc getGlobalAlpha*(n: Node): float
proc worldTransform*(n: Node): Matrix4

import rod.component

proc newNode*(name: string = nil): Node =
    result.new()
    result.mScale = newVector3(1, 1, 1)
    result.mRotation = newQuaternion()
    result.children = @[]
    result.name = name
    result.alpha = 1.0
    result.isDirty = true

proc setDirty(n: Node) =
    if n.isDirty == false:
        n.isDirty = true
        for c in n.children:
            c.setDirty()

template translation*(n: Node): Vector3 {.deprecated.} = n.mTranslation
proc `translation=`*(n: Node, p: Vector3) {.deprecated.} =
    n.mTranslation = p
    n.setDirty()

proc `translate=`*(n: Node, p: Vector3) =
    n.mTranslation += p
    n.setDirty()
proc `translateX=`*(n: Node, vx: float) =
    n.mTranslation.x += vx
    n.setDirty()
proc `translateY=`*(n: Node, vy: float) =
    n.mTranslation.y += vy
    n.setDirty()
proc `translateZ=`*(n: Node, vz: float) =
    n.mTranslation.z += vz
    n.setDirty()

proc position*(n: Node): Vector3 = n.mTranslation
proc positionX*(n: Node): Coord = n.mTranslation.x
proc positionY*(n: Node): Coord = n.mTranslation.y
proc positionZ*(n: Node): Coord = n.mTranslation.z

proc `position=`*(n: Node, p: Vector3) =
    n.mTranslation = p
    n.setDirty()
proc `positionX=`*(n: Node, x: Coord) =
    n.mTranslation.x = x
    n.setDirty()
proc `positionY=`*(n: Node, y: Coord) =
    n.mTranslation.y = y
    n.setDirty()
proc `positionZ=`*(n: Node, z: Coord) =
    n.mTranslation.z = z
    n.setDirty()

proc rotation*(n: Node): Quaternion = n.mRotation
proc `rotation=`*(n: Node, r: Quaternion) =
    n.mRotation = r
    n.setDirty()
proc `rotationX=`*(n: Node, vx: float) =
    n.mRotation.x = vx
    n.setDirty()
proc `rotationY=`*(n: Node, vy: float) =
    n.mRotation.y = vy
    n.setDirty()
proc `rotationZ=`*(n: Node, vz: float) =
    n.mRotation.z = vz
    n.setDirty()
proc `rotationW=`*(n: Node, vw: float) =
    n.mRotation.w = vw
    n.setDirty()

template scale*(n: Node): Vector3 = n.mScale
proc scaleX*(n: Node): Coord = n.mScale.x
proc scaleY*(n: Node): Coord = n.mScale.y
proc scaleZ*(n: Node): Coord = n.mScale.z

proc `scale=`*(n: Node, s: Vector3) =
    n.mScale = s
    n.setDirty()
proc `scaleX=`*(n: Node, value: Coord) =
    n.mScale.x = value
    n.setDirty()
proc `scaleY=`*(n: Node, value: Coord) =
    n.mScale.y = value
    n.setDirty()
proc `scaleZ=`*(n: Node, value: Coord) =
    n.mScale.z = value
    n.setDirty()

proc parent*(n: Node): Node = n.mParent
proc `parent=`*(n: Node, p: Node) =
    n.mParent = p
    n.setDirty()

proc createComponentForNode(n: Node, name: string): Component =
    result = createComponent(name)
    result.node = n

    if not n.mSceneView.isNil:
        result.componentNodeWasAddedToSceneView()

proc addComponent*(n: Node, name: string): Component =
    if n.components.isNil:
        n.components = newSeq[Component]()

    result = createComponentForNode(n, name)
    n.components.add(result)

proc addComponent*(n: Node, T: typedesc): Component =
    result = n.addComponent(T.name)


proc getComponent*(n: Node, name: string): Component =
    if n.components.isNil:
        return nil

    for v in n.components:
        if v.className == name:
            return v

    return nil

proc getComponent*(n: Node, T: typedesc[Component]): T =
    if n.components.isNil:
        return nil

    for v in n.components:
        type TT = T
        if v of TT:
            return v.TT

    return nil

proc component*(n: Node, name: string): Component =
    result = n.getComponent(name)
    if result.isNil:
        result = n.addComponent(name)

proc component*(n: Node, T: typedesc[Component]): T =
    type TT = T
    result = TT(n.component(T.name))

proc componentIfAvailable*(n: Node, name: string): Component =
    result = n.getComponent(name)

proc componentIfAvailable*(n: Node, T: typedesc[Component]): T =
    result = n.getComponent(T)

proc setComponent*(n: Node, name: string, c: Component) =
    if n.components.isNil:
        n.components = newSeq[Component]()
    n.components.add(c)

proc removeComponent*(n: Node, name: string) =
    if not n.components.isNil:
        let c = n.getComponent(name)
        for i, comp in n.components:
            if comp == c:
                c.componentNodeWillBeRemovedFromSceneView()
                n.components.delete(i)

proc removeComponent*(n: Node, T: typedesc[Component]) = n.removeComponent(T.name)

proc update(n: Node) =
    if not n.components.isNil:
        for k, v in n.components:
            v.update()

proc recursiveUpdate*(n: Node) =
    n.update()
    for c in n.children: c.recursiveUpdate()

proc makeTransform(n: Node): Matrix4 =
    var rot = n.mRotation.toMatrix4()

    # // Set up final matrix with scale, rotation and translation
    result[0] = n.mScale.x * rot[0]; result[1] = n.mScale.x * rot[1]; result[2] = n.mScale.x * rot[2];
    result[4] = n.mScale.y * rot[4]; result[5] = n.mScale.y * rot[5]; result[6] = n.mScale.y * rot[6];
    result[8] = n.mScale.z * rot[8]; result[9] = n.mScale.z * rot[9]; result[10] = n.mScale.z * rot[10];
    result[12] = n.position.x;  result[13] = n.position.y; result[14] = n.position.z;

    # // No projection term
    result[3] = 0; result[7] = 0; result[11] = 0; result[15] = 1;


proc getTransform*(n: Node, mat: var Matrix4) =
    mat.multiply(n.makeTransform(), mat)

# Transformations
proc transform*(n: Node): Matrix4 =
    # if n.isDirty:
    n.mMatrix = n.makeTransform()
        # n.isDirty = false

    return n.mMatrix

proc recursiveDraw*(n: Node) =
    if n.alpha < 0.0000001: return
    let c = currentContext()
    var tr = n.mSceneView.viewProjMatrix * n.worldTransform()
    let oldAlpha = c.alpha
    c.alpha *= n.alpha

    c.withTransform tr:
        var hasPosteffectComponent = false
        if not n.components.isNil:
            for v in n.components:
                v.draw()
                hasPosteffectComponent = hasPosteffectComponent or v.isPosteffectComponent()

    if not hasPosteffectComponent:
        for c in n.children: c.recursiveDraw()
    c.alpha = oldAlpha


proc drawNode*(n: Node): bool =
    if n.alpha < 0.0000001: return
    var tr = n.mSceneView.viewProjMatrix * n.worldTransform()

    currentContext().withTransform tr:
        var hasPosteffectComponent = false
        if not n.components.isNil:
            for v in n.components:
                v.draw()
                hasPosteffectComponent = hasPosteffectComponent or v.isPosteffectComponent()

    result = hasPosteffectComponent

proc recursiveDraw*(n: Node, drawTable: var TableRef[int, seq[Node]]) =
    if n.layer == 0:
        if n.alpha < 0.0000001: return

        let c = currentContext()
        let oldAlpha = c.alpha
        c.alpha *= n.alpha
        var hasPosteffectComponent = n.drawNode()

        if not hasPosteffectComponent:
            for c in n.children:
                c.recursiveDraw(drawTable)

        c.alpha = oldAlpha

    else:
        var drawNodes = drawTable.getOrDefault(n.layer)
        if drawNodes.isNil:
            drawNodes = newSeq[Node]()

        drawNodes.add(n)
        drawTable[n.layer] = drawNodes

        for c in n.children:
            c .recursiveDraw(drawTable)

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


let nodeLoadRefTable = newTable[string, seq[proc(nodeValue: Node)]]()

template addNodeRef*(refNode: var Node, name: string) =
    let refProc = proc(nodeValue: Node) = refNode = nodeValue
    if name in nodeLoadRefTable:
        nodeLoadRefTable[name].add(refProc)
    else:
        # Hacky workaround for closure compiler
        var s = nodeLoadRefTable[name]
        s.add(refProc)
        nodeLoadRefTable[name] = s

proc checkNodeRefs(n: Node) =
    for k, v in nodeLoadRefTable:
        let foundNode = n.findNode(k)
        if not foundNode.isNil:
            for s in v:
                s(foundNode)

proc nodeWillBeRemovedFromSceneView*(n: Node) =
    if not n.components.isNil:
        for c in n.components: c.componentNodeWillBeRemovedFromSceneView()
    if not n.children.isNil:
        for c in n.children: c.nodeWillBeRemovedFromSceneView()
    n.mSceneView = nil

proc nodeWasAddedToSceneView*(n: Node, v: SceneView) =
    if n.mSceneView.isNil:
        n.mSceneView = v
        if not n.components.isNil:
            for c in n.components: c.componentNodeWasAddedToSceneView()
        if not n.children.isNil:
            for c in n.children: c.nodeWasAddedToSceneView(v)
    else:
        # There may be cases where this proc has already been called.
        # E.g. component adds child node to its node in
        # `componentNodeWasAddedToSceneView`.
        # In such case we don't have to do anything
        assert(n.mSceneView == v)

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
    c.setDirty()
    if not n.mSceneView.isNil:
        c.nodeWasAddedToSceneView(n.mSceneView)

proc newChild*(n: Node, childName: string = nil): Node =
    result = newNode(childName)
    n.addChild(result)

proc insertChild*(n, c: Node, index: int) =
    c.removeFromParent()
    n.children.insert(c, index)
    c.parent = n
    c.setDirty()
    if not n.mSceneView.isNil:
        c.nodeWasAddedToSceneView(n.mSceneView)

proc childNamed*(n: Node, name: string): Node =
    for c in n.children:
        if c.name == name: return c

proc translationFromMatrix(m: Matrix4): Vector3 = [m[12], m[13], m[14]]

proc worldTransform*(n: Node): Matrix4 =
    if n.isDirty:
        n.isDirty = false
        if n.parent.isNil:
            n.worldMatrix = n.transform
        else:
            let w = n.parent.worldTransform
            w.multiply(n.transform, n.worldMatrix)

    result = n.worldMatrix

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

proc `worldPos=`*(n: Node, p: Vector3) =
    if n.parent.isNil:
        n.position = p
    else:
        n.position = n.parent.worldToLocal(p)

proc visitProperties*(n: Node, p: var PropertyVisitor) =
    p.visitProperty("name", n.name)
    p.visitProperty("translation", n.position)
    p.visitProperty("worldPos", n.worldPos)
    p.visitProperty("scale", n.scale)
    p.visitProperty("rotation", n.rotation)
    p.visitProperty("alpha", n.alpha)

    p.visitProperty("tX", n.positionX, { pfAnimatable })
    p.visitProperty("tY", n.positionY, { pfAnimatable })
    p.visitProperty("tZ", n.positionZ, { pfAnimatable })
    p.visitProperty("sX", n.scaleX, { pfAnimatable })
    p.visitProperty("sY", n.scaleY, { pfAnimatable })
    p.visitProperty("sZ", n.scaleZ, { pfAnimatable })

    p.visitProperty("layer", n.layer)

proc reparentTo*(n, newParent: Node) =
    # Change parent of a node preserving its world transform
    let oldWorldTransform = n.worldTransform
    newParent.addChild(n)
    let newTransform = newParent.worldTransform.inversed() * oldWorldTransform
    n.mTranslation = translationFromMatrix(newTransform)

proc animationNamed*(n: Node, name: string, preserveHandlers: bool = false): Animation =
    if not n.animations.isNil:
        result = n.animations.getOrDefault(name)
        if not result.isNil and not preserveHandlers: result.removeHandlers()

proc registerAnimation*(n: Node, name: string, a: Animation) =
    if n.animations.isNil:
        n.animations = newTable[string, Animation]()
    n.animations[name] = a

proc getGlobalAlpha*(n: Node): float =
    result = n.alpha
    if not n.parent.isNil:
        result = result * n.parent.getGlobalAlpha()

# Serialization
proc newNodeFromJson*(j: JsonNode, s: Serializer): Node
proc deserialize*(n: Node, j: JsonNode, s: Serializer)

proc loadComposition*(n: Node, resourceName: string) =
    let fullPath = pathForResource(resourceName)
    loadJsonResourceAsync resourceName, proc(j: JsonNode) =
        pushParentResource(fullPath)
        let serializer = Serializer.new()
        n.deserialize(j, serializer)
        popParentResource()

proc loadComposition*(n: Node, j: JsonNode) =
    let serializer = Serializer.new()
    n.deserialize(j, serializer)

import rod.animation.property_animation

# proc deserialize*(n: Node, s: Serializer) =
#     proc toValue(j: JsonNode, s: var string) =
#         s = j.str

#     proc jsonNameForPropName(s: string): string =
#         case s
#         of "bEnableBackfaceCulling": "culling"
#         else: s

#     for k, v in n[].fieldPairs:
#         echo "deserialize mesh = ", k
#         jNode{jsonNameForPropName(k)}.toValue(v)


proc deserialize*(n: Node, j: JsonNode, s: Serializer) =
    if n.name.isNil:
        s.deserializeValue(j, "name", n.name)
    s.deserializeValue(j, "translation", n.position)
    s.deserializeValue(j, "scale", n.mScale)
    s.deserializeValue(j, "rotation", n.mRotation)
    s.deserializeValue(j, "alpha", n.alpha)
    s.deserializeValue(j, "layer", n.layer)

    var v = j{"children"}
    if not v.isNil:
        for i in 0 ..< v.len:
            n.addChild(newNodeFromJson(v[i], s))


    v = j{"components"}
    if not v.isNil:
        if v.kind == JArray:
            for i in 0 ..< v.len:
                var className: string
                s.deserializeValue(v[i], "_c", className)
                let comp = n.addComponent(className)
                comp.deserialize(v[i], s)
        else:
            # Deprecated. Old save format support
            for k, c in v:
                if k == "NodeSelector":
                    continue
                let comp = n.component(k)
                comp.deserialize(c, s)

    let animations = j{"animations"}
    if not animations.isNil and animations.len > 0:
        n.animations = newTable[string, Animation]()
        for k, v in animations:
            n.animations[k] = newPropertyAnimation(n, v)

    let compositionRef = j{"compositionRef"}.getStr(nil)
    if not compositionRef.isNil and not n.name.endsWith(".placeholder"):
        n.loadComposition(compositionRef)

proc newNodeFromJson*(j: JsonNode, s: Serializer): Node =
    result = newNode()
    result.deserialize(j, s)

proc newNodeWithResource*(name: string): Node =
    result = newNode()
    result.loadComposition(name)

    result.checkNodeRefs()
    nodeLoadRefTable.clear()

proc newNodeWithCompositionName*(name: string): Node {.deprecated.} =
    result = newNode()
    result.loadComposition("compositions/" & name & ".json")

proc serialize*(n: Node, s: Serializer): JsonNode =
    result = newJObject()
    result.add("name", s.getValue(n.name))
    result.add("translation", s.getValue(n.position))
    result.add("scale", s.getValue(n.scale))
    result.add("rotation", s.getValue(n.rotation))
    result.add("alpha", s.getValue(n.alpha))
    result.add("layer", s.getValue(n.layer))

    if not n.components.isNil:
        var componentsNode = newJArray()
        result.add("components", componentsNode)

        for value in n.components:
            if value.className() == "NodeSelector":
                continue

            var jcomp: JsonNode
            jcomp = value.serialize( s )

            if not jcomp.isNil:
                jcomp.add("_c", %value.className())
                componentsNode.add(jcomp)

    var childsNode = newJArray()
    result.add("children", childsNode)
    for child in n.children:
        childsNode.add( child.serialize(s) )

proc getDepth*(n: Node): int =
    result = 0

    var p = n.parent
    while not p.isNil:
        inc result
        p = p.parent

proc printParents(n: Node, indent: var string) =
    echo "" & indent & " name ", n.name
    indent = indent & "+"
    if not n.parent.isNil:
        n.parent.printParents(indent)

proc getTreeDistance*(x, y: Node): int =
    assert(x != y)

    let xxLevel = x.getDepth()
    let yyLevel = y.getDepth()
    var xLevel = xxLevel
    var yLevel = yyLevel
    var px = x
    var py = y

    while xLevel > yLevel:
        dec xLevel
        px = px.parent
    while yLevel > xLevel:
        dec yLevel
        py = py.parent

    if px == py:
        # One node is child of another
        if xxLevel > yyLevel:
            return -1
        else:
            return 1

    #assert(px != py)
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


proc rayCast*(n: Node, r: Ray, castResult: var seq[RayCastInfo]) =
    if not n.components.isNil:
        for name, component in n.components:
            var distance: float32
            let res = component.rayCast(r, distance)

            if res:
                var castInfo: RayCastInfo
                castInfo.node = n
                castInfo.distance = distance
                castResult.add(castInfo)

    for c in n.children:
        c.rayCast(r, castResult)

# Debugging
proc recursiveChildrenCount*(n: Node): int =
    result = n.children.len
    for c in n.children:
        result += c.recursiveChildrenCount
