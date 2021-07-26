import nimx / [ context, types, animation, image, portable_gl, view, property_visitor, pathutils ]
import nimx / assets / [ asset_manager, asset_loading ]
import rod / utils / [ bin_deserializer, json_serializer, json_deserializer ]
import rod / [ asset_bundle ]
import rod / tools / serializer
import rod / [ node_2, node_flags ]
import quaternion, ray, rod_types
import tables, typetraits, json, strutils, math, os
export node_2, node_flags

when defined(rodedit):
    import rod / editor / scene / components / editor_component

export Node

type NodeAnchorAUX* = ref object
    node*: Node

proc sceneView*(n: Node): SceneView = n.mSceneView
proc getGlobalAlpha*(n: Node): float32
proc worldTransform*(n: Node): Matrix4
proc isEnabledInTree*(n: Node): bool

import rod/component

iterator components*(n: Node): Component =
    for c in n.renderComponents: yield c
    for c in n.scriptComponents: yield c

proc animationRunner(n: Node): AnimationRunnerComponent

proc addAnimation*(n: Node, a: Animation) =
    n.animationRunner.runner.pushAnimation(a)

proc removeAnimation*(n: Node, a: Animation) =
    n.animationRunner.runner.removeAnimation(a)

proc newNode*(name: string = ""): Node =
    result.new()
    result.mScale = newVector3(1, 1, 1)
    result.mRotation = newQuaternion()

    result.name = name
    result.alpha = 1.0
    result.isDirty = true
    result.isEnabled = true
    result.affectsChildren = true
    result.isSerializable = true

    result.mParent = InvalidNodeIndex
    result.mIndex = InvalidNodeIndex
    result.mNext = InvalidNodeIndex
    result.mPrev = InvalidNodeIndex
    result.mFirstChild = InvalidNodeIndex



template translation*(n: Node): Vector3 {.deprecated.} = n.mTranslation
proc `translation=`*(n: Node, p: Vector3) {.deprecated.} =
    n.mTranslation = p
    n.setDirty()

template enabled*(n: Node): bool = n.isEnabled
proc `enabled=`*(n: Node, v: bool) =
    n.isEnabled = v
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

proc `anchor=`*(n: Node, v: Vector3) =
    n.mAnchorPoint = v
    n.setDirty()

proc anchor*(n: Node): Vector3 =
    result = n.mAnchorPoint

proc createComponentForNode(n: Node, name: string): Component =
    result = createComponent(name)
    result.node = n

    if not n.mSceneView.isNil:
        result.componentNodeWasAddedToSceneView()

proc addComponent*(n: Node, name: string): Component =
    result = createComponentForNode(n, name)
    if result.isRenderComponent():
        n.renderComponents.add(result.RenderComponent)
    else:
        n.scriptComponents.add(result.ScriptComponent)

proc addComponent*(n: Node, T: typedesc): T =
    type TT = T
    result = n.addComponent(T.name).TT

proc insertComponent(n: Node, c: Component, index: int)
proc addComponent*(n: Node, T: typedesc, index: int): T =
    type TT = T
    result = createComponent(T.name).TT
    result.node = n

    n.insertComponent(result, index)

proc getComponent*(n: Node, name: string): Component =
    for v in n.components:
        if v.className == name:
            return v

    return nil

proc getComponent*(n: Node, T: typedesc[Component]): T =
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

proc setComponent*(n: Node, name: string, c: Component) {.deprecated.} =
    if c.isRenderComponent:
        n.renderComponents.add(c.RenderComponent)
    else:
        n.scriptComponents.add(c.ScriptComponent)

proc insertComponent(n: Node, c: Component, index: int) =
    template inserAUX(components: untyped, c: untyped, index: int) =
        let i = clamp(index, 0, components.len)
        components.insert(c, i)
    if c.isRenderComponent:
        n.renderComponents.inserAUX(c.RenderComponent, index)
    else:
        n.scriptComponents.inserAUX(c.ScriptComponent, index)
    c.componentNodeWasAddedToSceneView()

proc removeComponent*(n: Node, c: Component) =
    template removeCompAUX(components: untyped, c: untyped) =
        let compPos = components.find(c)
        if compPos > -1:
            c.componentNodeWillBeRemovedFromSceneView()
            components.delete(compPos)
    if c.isNil: return

    if c.isRenderComponent:
        n.renderComponents.removeCompAUX(c.RenderComponent)
    else:
        n.scriptComponents.removeCompAUX(c.ScriptComponent)

proc removeComponent*(n: Node, name: string) =
    let c = n.getComponent(name)
    n.removeComponent(c)

proc removeComponent*(n: Node, T: typedesc[Component]) = n.removeComponent(T.name)

proc animationRunner(n: Node): AnimationRunnerComponent =
    result = n.component(AnimationRunnerComponent)

proc recursiveUpdate*(n: Node, dt: float) =
    if not n.enabled: return
    for comp in n.scriptComponents:
        comp.update(dt)
    for c in n.children:
        c.recursiveUpdate(dt)

proc anchorMatrix(n: Node): Matrix4=
    result[0] = 1; result[1] = 0; result[2] = 0;
    result[4] = 0; result[5] = 1; result[6] = 0;
    result[8] = 0; result[9] = 0; result[10] = 1;
    result[12] = -n.mAnchorPoint.x;  result[13] = -n.mAnchorPoint.y; result[14] = -n.mAnchorPoint.z;
    result[15] = 1;

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
    n.mMatrix = n.makeTransform() * n.anchorMatrix()
    return n.mMatrix

proc drawNode*(n: Node, recursive: bool) =
    if n.alpha < 0.0000001 or not n.enabled: return

    var tr: Transform3d
    let c = currentContext()

    let oldAlpha = c.alpha
    c.alpha *= n.alpha

    var lastDrawComp = -1
    var hasPosteffectComponent = false

    var compLen = n.renderComponents.len
    var componentInterruptedDrawing = false

    if compLen > 0:
        tr = n.mSceneView.viewProjMatrix * n.worldTransform()
        c.withTransform tr:
            for c in n.renderComponents:
                inc lastDrawComp
                if c.beforeDraw(lastDrawComp):
                    componentInterruptedDrawing = true
                    break

            # Legacy api support. Will be removed soon.
            for c in n.renderComponents:
                c.draw()
                when defined(rodedit):
                    c.onDrawGizmo()
                hasPosteffectComponent = hasPosteffectComponent or c.isPosteffectComponent()

    let shouldDrawChildren = recursive and not hasPosteffectComponent

    if shouldDrawChildren and n.affectsChildren and not componentInterruptedDrawing:
        for c in n.children:
            c.drawNode(recursive)

    assert(compLen == n.renderComponents.len, "Components changed during drawing.")
    if compLen > 0:
        c.withTransform tr:
            while lastDrawComp >= 0:
                n.renderComponents[lastDrawComp].afterDraw(lastDrawComp)
                dec lastDrawComp

    if shouldDrawChildren and not n.affectsChildren:
        for c in n.children:
            c.drawNode(recursive)

    c.alpha = oldAlpha

template recursiveDraw*(n: Node) =
    n.drawNode(true)

iterator allNodes*(n: Node): Node =
    var s = @[n]
    var i = 0
    while i < s.len:
        let n = s[i]
        yield n
        for ch in n.children:
            s.add(ch)
        inc i

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

proc findNode*(n: Node, parts: openarray[string]): Node =
    if parts.len == 0:
        raise newException(Exception, "Invalid search path (len == 0)")
    var i = 0
    var p: Node
    # starts from `/`, searching from rootNode
    if parts[0].len == 0:
        if n.sceneView.isNil:
            raise newException(Exception, "SceneView is nil")
        p = n.sceneView.mRootNode
        inc i
    # searching from this node
    else:
        p = n

    while i < parts.len and not p.isNil:
        if parts[i] == "..":
            p = p.parent
        else:
            p = p.findNode(parts[i])
        inc i
    result = p

type
    NodeRefResolveProc* = proc(nodeValue: Node)
    NodeRefTable = TableRef[string, seq[NodeRefResolveProc]]

var nodeLoadRefTable*: NodeRefTable

proc addNodeRef*(name: string, refProc: proc(n: Node)) =
    assert(not nodeLoadRefTable.isNil)
    if name in nodeLoadRefTable:
        nodeLoadRefTable[name].add(refProc)
    else:
        nodeLoadRefTable[name] = @[refProc]

template addNodeRef*(refNode: var Node, name: string) {.deprecated.} =
    addNodeRef(name) do(n: Node):
        refNode = n

template addNodeRef*(name: string, refNode: var Node) =
    addNodeRef(name) do(n: Node):
        refNode = n

proc resolveNodeRefs(n: Node) =
    assert(not nodeLoadRefTable.isNil)
    for k, v in nodeLoadRefTable:
        let foundNode = n.findNode(k)
        if not foundNode.isNil:
            for s in v:
                s(foundNode)

proc nodeWillBeRemovedFromSceneView*(n: Node) =
    block components:
        template removedAUX(components: untyped) =
            var ci = 0
            while ci < components.len:
                components[ci].componentNodeWillBeRemovedFromSceneView()
                inc ci

        n.renderComponents.removedAUX()
        n.scriptComponents.removedAUX()


    let children = n.seqOfChildren
    var ci = 0
    while ci < children.len:
        children[ci].nodeWillBeRemovedFromSceneView()
        inc ci
    n.mSceneView = nil

proc nodeWasAddedToSceneView*(n: Node, v: SceneView) =
    if n.mSceneView.isNil:
        n.mSceneView = v
        block components:
            template addedAUX(components: untyped) =
                let size = components.len
                var ci = 0
                while ci < size:
                    components[ci].componentNodeWasAddedToSceneView()
                    inc ci

            n.renderComponents.addedAUX()
            n.scriptComponents.addedAUX()

        let children = n.seqOfChildren
        var ci = 0
        while ci < children.len:
            children[ci].nodeWasAddedToSceneView(v)
            inc ci
    else:
        # There may be cases where this proc has already been called.
        # E.g. component adds child node to its node in
        # `componentNodeWasAddedToSceneView`.
        # In such case we don't have to do anything
        assert(n.mSceneView == v)

# proc removeChild(n, child: Node) =
#     for i, c in n.children:
#         if c == child:
#             n.children.delete(i)
#             break

        # c.parent = nil
#     n.children.setLen(0)

proc removeFromParent*(n: Node) =
    if not n.parent.isNil:
        if not n.mSceneView.isNil:
            n.nodeWillBeRemovedFromSceneView()
    n.removeFromParent2()
#         n.parent.removeChild(n)
#         n.parent = nil

#todo: think about it
proc removeAllChildren*(n: Node) =
    var toRemove: seq[Node]
    for c in n.children:
        toRemove.add(n)

    var i = 0
    while i < toRemove.len:
        toRemove[i].removeFromParent()
        inc i

proc addChild*(n, c: Node) =
    n.addChild2(c)
    # c.removeFromParent()
    # n.children.add(c)
    # c.parent = n
    c.setDirty()
    if not n.mSceneView.isNil:
        c.nodeWasAddedToSceneView(n.mSceneView)

proc newChild*(n: Node, childName: string): Node =
    result = newNode(childName)
    n.addChild(result)

proc newChild*(n: Node): Node {.inline.} = newChild(n, "")

proc insertChild*(n, c: Node, index: int) =
    n.insertChild2(c, index)
    # c.removeFromParent()
    # n.children.insert(c, index)
    # c.parent = n
    c.setDirty()
    if not n.mSceneView.isNil:
        c.nodeWasAddedToSceneView(n.mSceneView)

proc childNamed*(n: Node, name: string): Node =
    for c in n.children:
        if c.name == name: return c

proc setBoneMatrix*(n: Node, mat: Matrix4) =
    n.isDirty = false
    mat.multiply(n.transform, n.worldMatrix)

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
    result = n.localToWorld(n.mAnchorPoint)

proc `worldPos=`*(n: Node, p: Vector3) =
    if n.parent.isNil:
        n.position = p
    else:
        var r: Vector3
        if n.parent.tryWorldToLocal(p, r):
            n.position = r

proc nodeBounds(n: Node, minP: var Vector3, maxP: var Vector3) =
    # TODO: think about Z coordinate
    let wrldMat = n.worldTransform()
    var wp0, wp1, wp2, wp3: Vector3
    var bb: BBox
    for comp in n.components:
        bb = comp.getBBox()
        if not bb.isEmpty:
            wp0 = wrldMat * bb.minPoint
            wp1 = wrldMat * newVector3(bb.minPoint.x, bb.maxPoint.y, bb.minPoint.z)
            wp2 = wrldMat * bb.maxPoint
            wp3 = wrldMat * newVector3(bb.maxPoint.x, bb.minPoint.y, bb.maxPoint.z)

            minP.x = min(minP.x, min(wp0.x, min(wp1.x, min(wp2.x, wp3.x))))
            minP.y = min(minP.y, min(wp0.y, min(wp1.y, min(wp2.y, wp3.y))))
            maxP.x = max(maxP.x, max(wp0.x, max(wp1.x, max(wp2.x, wp3.x))))
            maxP.y = max(maxP.y, max(wp0.y, max(wp1.y, max(wp2.y, wp3.y))))

            minP.z = min(minP.z, min(wp0.z, min(wp1.z, min(wp2.z, wp3.z))))
            maxP.z = max(maxP.z, max(wp0.z, max(wp1.z, max(wp2.z, wp3.z))))

    for ch in n.children:
        if ch.enabled and ch.alpha > 0.001 and ch.scale.x > 0.001 and ch.scale.y > 0.001:
            ch.nodeBounds(minP, maxP)

proc nodeBounds*(n: Node): BBox =
    result.minPoint = newVector3(high(int).float, high(int).float, high(int).float)
    result.maxPoint = newVector3(low(int).float, low(int).float, low(int).float)
    n.nodeBounds(result.minPoint, result.maxPoint)

proc visitProperties*(n: Node, p: var PropertyVisitor) =
    p.visitProperty("name", n.name)
    p.visitProperty("translation", n.position)
    p.visitProperty("worldPos", n.worldPos)
    p.visitProperty("scale", n.scale)
    p.visitProperty("rotation", n.rotation)
    p.visitProperty("anchor", n.anchor)

    when defined(rodedit):
        var mAnch = NodeAnchorAUX(node: n)
        p.visitProperty("anchorSetter", mAnch, { pfEditable })
    p.visitProperty("alpha", n.alpha)
    p.visitProperty("affectsCh", n.affectsChildren, { pfEditable })

    p.visitProperty("tX", n.positionX, { pfAnimatable })
    p.visitProperty("tY", n.positionY, { pfAnimatable })
    p.visitProperty("tZ", n.positionZ, { pfAnimatable })
    p.visitProperty("sX", n.scaleX, { pfAnimatable })
    p.visitProperty("sY", n.scaleY, { pfAnimatable })
    p.visitProperty("sZ", n.scaleZ, { pfAnimatable })

    p.visitProperty("enabled", n.enabled)

proc reparentTo*(n, newParent: Node) {.deprecated.} =
    # Change parent of a node preserving its world transform
    let oldWorldTransform = n.worldTransform
    newParent.addChild(n)
    let newTransform = newParent.worldTransform.inversed() * oldWorldTransform
    n.mTranslation = translationFromMatrix(newTransform)

proc reattach*(n, newParent: Node, index = -1) =
    let worldTransform = n.worldTransform
    let worldPos = n.worldPos

    var inv_mat: Matrix4
    if tryInverse(newParent.worldTransform(), inv_mat) == false:
        return

    let localMatrix = worldTransform * inv_mat
    var localScale = newVector3(1.0)
    var localRotation: Vector4
    discard localMatrix.tryGetScaleRotationFromModel(localScale, localRotation)

    if index >= 0:
        newParent.insertChild(n, index)
    else:
        newParent.addChild(n)

    n.worldPos = worldPos
    n.scale = localScale
    n.rotation = Quaternion(localRotation)

proc animationNamed*(n: Node, name: string, preserveHandlers: bool = false): Animation =
    if not n.animations.isNil:
        result = n.animations.getOrDefault(name)
        if not result.isNil and not preserveHandlers: result.removeHandlers()

proc registerAnimation*(n: Node, name: string, a: Animation) =
    if n.animations.isNil:
        n.animations = newTable[string, Animation]()
    n.animations[name] = a

proc getGlobalAlpha*(n: Node): float32 =
    var p = n
    result = 1

    while not p.isNil:
        result *= p.alpha
        p = p.parent

proc isEnabledInTree*(n: Node): bool =
    var p = n
    while not p.isNil:
        if not p.enabled: return false
        p = p.parent
    return true

# Serialization
proc deserialize*(n: Node, s: JsonDeserializer)

proc loadNodeFromJson*(n: Node, j: JsonNode, url: string = "") =
    let deser = newJsonDeserializer()
    const prefix = "file://"
    doAssert(url.startsWith(prefix), "Internal error")
    deser.compPath = url[prefix.len ..  ^1]
    deser.getImageForPath = proc(p: string, off: var Point): Image =
        when not defined(js) and not defined(emscripten):
            # TODO: We have to figure out smth about js...
            result = imageWithContentsOfFile(p)

    let oldNodeRefTab = nodeLoadRefTable
    nodeLoadRefTable = newTable[string, seq[NodeRefResolveProc]]()
    defer: nodeLoadRefTable = oldNodeRefTab

    deser.node = j
    n.deserialize(deser)
    n.resolveNodeRefs()

proc loadNodeFromJson*(n: Node, j: JsonNode, url: string = "", onComplete: proc()) {.deprecated.} =
    n.loadNodeFromJson(j, url)
    if not onComplete.isNil: onComplete()

proc binDeserializerForPath(path: string): BinDeserializer =
    let am = sharedAssetManager()
    let ab = am.assetBundleForPath(path)
    var rab: AssetBundle
    if ab of AssetBundle: rab = AssetBundle(ab)
    if not rab.isNil:
        return rab.binDeserializer

proc newNode*(b: BinDeserializer, compName: string, c: Composition): Node

proc fixupCompositionUrlExtension(url: var string)=
    ## Makes sure the extension is jcomp
    if url.endsWith(".json"):
        url = url.changeFileExt("jcomp")
    elif not url.endsWith(".jcomp"):
        url &= ".jcomp"

proc newComposition*(url: string, n: Node = nil): Composition =
    result.new()
    result.url = url
    result.node = if not n.isNil: n else: newNode()
    result.node.composition = result

proc loadComposition*(comp: Composition, onComplete: proc() = nil) =
    const prefix = "res://"
    if comp.url.startsWith(prefix):
        let path = comp.url.substr(prefix.len)
        let bd = binDeserializerForPath(path)
        if not bd.isNil:
            try:
                let theNode = newNode(bd, path, comp)
                comp.node[] = theNode[]
                for c in comp.node.children:
                    c.parent = comp.node
                for c in comp.node.components:
                    c.node = comp.node

                if not onComplete.isNil:
                    onComplete()
                return
            except:
                echo "Error: could not deserialize ", path
                raise
        else:
            echo "No BinDeserializer for ", path

    fixupCompositionUrlExtension(comp.url)
    loadAsset(comp.url) do(j: JsonNode, err: string):
        assert err.len == 0, err

        try:
            comp.node.loadNodeFromJson(j, comp.url, onComplete)
        except:
            echo "Could not deserialize ", comp.url, ": ", getCurrentExceptionMsg()
            echo getCurrentException().getStackTrace()
            raise

import rod/animation/property_animation

proc deserialize*(n: Node, s: JsonDeserializer) =
    assert(s.compPath.len != 0)
    let j = s.node
    var v = j{"children"}
    if not v.isNil:
        for i in 0 ..< v.len:
            s.node = v[i]
            let c = newNode()
            c.deserialize(s)
            n.addChild(c)
        s.node = j

    v = j{"components"}
    if not v.isNil:
        if v.kind == JArray:
            for i in 0 ..< v.len:
                s.node = v[i]
                var className: string
                s.visit(className, "_c")
                let comp = n.addComponent(className)
                comp.deserialize(s)
            s.node = j
        else:
            doAssert(false, "Old save format")

    let compositionRef = j{"compositionRef"}.getStr()
    if compositionRef.len != 0:
        var p = parentDir(s.compPath) / compositionRef
        normalizePath(p, false)
        newComposition("file://" & p, n).loadComposition()

    s.visit(n.name, "name")
    s.visit(n.mTranslation, "translation")
    s.visit(n.mScale, "scale")
    s.visit(n.mRotation, "rotation")
    s.visit(n.mAnchorPoint, "anchor")
    s.visit(n.alpha, "alpha")
    n.isEnabled = s.node{"enabled"}.getBool(true)
    n.affectsChildren = s.node{"affectsChildren"}.getBool(true)

    let animations = j{"animations"}
    if not animations.isNil and animations.len > 0:
        n.animations = newTable[string, Animation]()
        for k, v in animations:
            n.animations[k] = newPropertyAnimation(n, v)

    when defined(rodedit):
        n.jAnimations = animations

proc newNodeWithUrl*(url: string): Node {.deprecated.} =
    let c = newComposition(url)
    result = c.node
    c.loadComposition()

proc newNodeWithResource*(path: string): Node =
    let bd = binDeserializerForPath(path)
    if not bd.isNil:
        try:
            #todo: fix this
            var comp = newComposition(path)
            comp.node[] = newNode(bd, path, comp)[]
            return comp.node
        except:
            echo "Error: could not deserialize ", path
            raise
    else:
        echo "No BinDeserializer for ", path
    when defined(rodedit):
        let c = newComposition("file://res/" & path)
    else:
        let c = newComposition("res://" & path)
    var done = false
    c.loadComposition() do():
        done = true
    when defined(rodedit):
        if true: return c.node
    if not done:
        raise newException(Exception, "newNodeWithResource(" & path & ") could not complete synchronously. Possible reason: needed asset bundles are not preloaded.")
    result = c.node

proc serialize*(n: Node, s: JsonSerializer) =
    s.visit(n.name, "name")
    s.visit(n.position, "translation")
    s.visit(n.scale, "scale")
    s.visit(n.rotation, "rotation")
    s.visit(n.anchor, "anchor")
    s.visit(n.alpha, "alpha")
    s.visit(n.affectsChildren, "affectsChildren")
    s.visit(n.enabled, "enabled")

    if not n.composition.isNil:
        s.visit(n.composition.url, "compositionRef")
        let aeLayer = n.componentIfAvailable("AELayer")
        if not aeLayer.isNil:
            let jn = s.node
            jn["components"] = newJArray()
            s.node = newJObject()
            aeLayer.serialize(s)
            jn["components"].add(s.node)
            s.node = jn
        return

    if n.renderComponents.len > 0 or n.scriptComponents.len > 0:
        let jn = s.node
        let jcomps = newJArray()
        jn["components"] = jcomps
        for c in n.components:
            s.node = newJObject()
            c.serialize(s)
            doAssert("_c" in s.node, "component did not serialize properly: " & c.className())
            jcomps.add(s.node)
        s.node = jn

    if n.hasChildren:
        let jn = s.node
        let jchildren = newJArray()
        jn["children"] = jchildren
        for child in n.children:
            when defined(rodedit):
                if not child.isSerializable: continue
            s.node = newJObject()
            child.serialize(s)
            jchildren.add(s.node)
        s.node = jn

    when defined(rodedit):
        if not n.jAnimations.isNil:
            s.node["animations"] = n.jAnimations

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

    var cx, cy : Node
    while px != py:
        cx = px
        cy = py
        px = px.parent
        py = py.parent

    assert(not cx.isNil and not cy.isNil)

    let ix = px.indexOf(cx)
    let iy = px.indexOf(cy)

    result = iy - ix

proc rayCast*(n: Node, r: Ray, castResult: var seq[RayCastInfo]) =
    if n.getGlobalAlpha() < 0.01 or not n.isEnabledInTree():
        return

    var inv_mat: Matrix4
    if tryInverse(n.worldTransform(), inv_mat):
        let localRay = r.transform(inv_mat)
        for component in n.components:
            var distance: float32
            let res = component.rayCast(localRay, distance)

            if res:
                var castInfo: RayCastInfo
                castInfo.node = n
                castInfo.distance = distance
                castResult.add(castInfo)

        for c in n.children:
            c.rayCast(r, castResult)

# Debugging
proc recursiveChildrenCount*(n: Node): int =
    for c in n.children:
        inc result
        result += c.recursiveChildrenCount

type
    BuiltInComponentType* = enum # This is a copypaste from binformat. TODO: Remove
        bicAlpha = "A"
        bicFlags = "f"
        bicAnchorPoint = "a"
        bicCompRef = "c"
        bicName = "n"
        bicRotation = "r"
        bicScale = "s"
        bicTranslation = "t"

proc newNode*(b: BinDeserializer, compName: string, c: Composition): Node =
    let oldPos = b.getPosition()
    let oldPath = b.curCompPath
    b.curCompPath = compName

    let oldNodeRefTab = nodeLoadRefTable
    nodeLoadRefTable = newTable[string, seq[NodeRefResolveProc]]()
    defer: nodeLoadRefTable = oldNodeRefTab

    b.rewindToComposition(compName)
    let nodesCount = b.readInt16()
    var nodes = newSeq[Node](nodesCount)
    for i in 0 ..< nodesCount:
        nodes[i] = newNode()

    var tmpBuf = b.getBuffer(int16, nodesCount - 1)
    # Read child-parent relations
    for i in 1 ..< nodesCount:
        let ch = nodes[i]
        let p = nodes[tmpBuf[i - 1]]
        #todo: fix this
        p.addChild2(ch)
        # ch.parent = p

    let compsCount = b.readInt16()
    for i in 0 ..< compsCount:
        let name = b.readStr()
        case name
        of $bicAlpha:
            let alphas = b.getBuffer(uint8, nodesCount)
            for i in 0 ..< nodesCount:
                nodes[i].alpha = float32(alphas[i]) / 255
        of $bicFlags:
            let flags = b.getBuffer(uint8, nodesCount)
            for i in 0 ..< nodesCount:
                nodes[i].isEnabled = (flags[i] and (1.uint8 shl NodeFlags.enabled.uint8)) != 0
                nodes[i].affectsChildren = (flags[i] and (1.uint8 shl NodeFlags.affectsChildren.uint8)) != 0
        of $bicAnchorPoint:
            let count = b.readInt16()
            tmpBuf = b.getBuffer(int16, count)
            let anchorPoints = b.getBuffer(Vector3, count)
            for i in 0 ..< count:
                nodes[tmpBuf[i]].mAnchorPoint = anchorPoints[i]
        of $bicTranslation:
            let count = b.readInt16()
            tmpBuf = b.getBuffer(int16, count)
            let translations = b.getBuffer(Vector3, count)
            for i in 0 ..< count:
                nodes[tmpBuf[i]].mTranslation = translations[i]
        of $bicScale:
            let count = b.readInt16()
            tmpBuf = b.getBuffer(int16, count)
            let scales = b.getBuffer(Vector3, count)
            for i in 0 ..< count:
                nodes[tmpBuf[i]].mScale = scales[i]
        of $bicRotation:
            let count = b.readInt16()
            tmpBuf = b.getBuffer(int16, count)
            let rotations = b.getBuffer(Quaternion, count)
            for i in 0 ..< count:
                nodes[tmpBuf[i]].mRotation = rotations[i]
        of $bicName:
            for i in 0 ..< nodesCount:
                nodes[i].name = b.readStr()
        of $bicCompRef:
            let count = b.readInt16()
            tmpBuf = b.getBuffer(int16, count)
            for i in 0 ..< count:
                let compRef = b.readStr()
                let subComp = newNodeWithResource(compRef)
                let old = nodes[tmpBuf[i]]

                # for c in subComp.children:
                #     c.parent = old

                var subCompCh = subComp.seqOfChildren
                if old.hasChildren:
                    for i, ch in subCompCh:
                        old.insertChild2(ch, i)
                    # old.children = subComp.children & old.children
                else:
                    for ch in subCompCh:
                        old.addChild2(ch)
                    # old.children = subComp.children
                old.animations = subComp.animations
                for c in subComp.components:
                    c.node = old
                old.renderComponents.add(subComp.renderComponents)
                old.scriptComponents.add(subComp.scriptComponents)
        else:
            let count = b.readInt16()
            tmpBuf = b.getBuffer(int16, count)
            for i in 0 ..< count:
                let comp = nodes[tmpBuf[i]].addComponent(name)
                comp.deserialize(b)

    result = nodes[0]

    let animationsCount = b.readInt16()
    if animationsCount > 0:
        result.animations = newTable[string, Animation]()
        for i in 0 ..< animationsCount:
            let name = b.readStr()
            result.animations[name] = newPropertyAnimation(result, b, false)

    result.resolveNodeRefs()
    b.setPosition(oldPos)
    b.curCompPath = oldPath
