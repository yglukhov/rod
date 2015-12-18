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

# import rod.component.light

type
    Node3D* = ref object
        translation*: Vector3
        rotation*: Quaternion
        scale*: Vector3
        components*: TableRef[string, Component]
        children*: seq[Node3D]
        parent*: Node3D
        name*: string
        animations*: TableRef[string, Animation]
        mViewport*: Viewport

    Component* = ref object of RootObj
        node*: Node3D

    CameraProjection* = enum
        cpOrtho, # Auto
        cpPerspective, # Auto
        cpManual

    Camera* = ref object of Component
        projectionMode*: CameraProjection
        zNear*, zFar*: Coord
        mManualGetProjectionMatrix*: proc(viewportBounds: Rect, mat: var Matrix4)

    Viewport* = ref object
        mCamera*: Camera
        mRootNode*: Node3D
        view*: View
        numberOfNodesWithBackComposition*: int
        numberOfNodesWithBackCompositionInCurrentFrame*: int
        mActiveFrameBuffer*, mBackupFrameBuffer*: SelfContainedImage
        mScreenFrameBuffer*: GLuint
        tempFramebuffers*: seq[SelfContainedImage]
        # passID
        # renderPath
        # observ
        light*: Component

type Node2D* = Node3D
type Node* = Node3D

proc viewport*(n: Node2D): Viewport = n.mViewport

import rod.component

proc newNode*(name: string = nil): Node =
    result.new()
    result.scale = newVector3(1, 1, 1)
    result.rotation = newQuaternion()
    result.children = @[]
    result.name = name

proc createComponentForNode(n: Node2D, name: string): Component =
    result = createComponent(name)
    result.node = n
    if not n.mViewport.isNil:
        result.componentNodeWasAddedToViewport()

proc component*(n: Node2D, name: string): Component =
    if n.components.isNil:
        n.components = newTable[string, Component]()
        result = createComponentForNode(n, name)
        n.components[name] = result
    else:
        result = n.components.getOrDefault(name)
        if result.isNil:
            result = createComponentForNode(n, name)
            n.components[name] = result

proc component*(n: Node2D, T: typedesc[Component]): T =
    type TT = T
    result = TT(n.component(T.name))

proc componentIfAvailable*(n: Node2D, name: string): Component =
    if not n.components.isNil:
        result = n.components.getOrDefault(name)

proc componentIfAvailable*(n: Node2D, T: typedesc[Component]): T =
    type TT = T
    result = TT(n.componentIfAvailable(T.name))

proc setComponent*(n: Node2D, name: string, c: Component) =
    if n.components.isNil:
        n.components = newTable[string, Component]()
    n.components[name] = c

proc removeComponent*(n: Node2D, name: string) =
    if not n.components.isNil:
        let c = n.components.getOrDefault(name)
        if not c.isNil:
            c.componentNodeWillBeRemovedFromViewport()
            n.components.del(name)

proc removeComponent*(n: Node2D, T: typedesc[Component]) = n.removeComponent(T.name)

proc update(n: Node2D) =
    for k, v in n.components:
        v.update()

proc recursiveUpdate*(n: Node2D) =
    n.update()
    for c in n.children: c.recursiveUpdate()

proc getTransform*(n: Node2D, mat: var Matrix4) =
    mat.translate(n.translation)
    mat.multiply(n.rotation.toMatrix4(), mat)
    mat.scale(n.scale)

# Transformations
proc transform*(n: Node2D): Matrix4 =
    result.loadIdentity()
    n.getTransform(result)

proc recursiveDraw*(n: Node2D) =
    let c = currentContext()
    var tr = c.transform
    n.getTransform(tr)
    c.withTransform tr:
        var hasPosteffectComponent = false
        if not n.components.isNil:
            for k, v in n.components:
                v.draw()
                hasPosteffectComponent = hasPosteffectComponent or v.isPosteffectComponent()
        if not hasPosteffectComponent:
            for c in n.children: c.recursiveDraw()

proc nodeWillBeRemovedFromViewport*(n: Node2D) =
    if not n.components.isNil:
        for c in n.components.values: c.componentNodeWillBeRemovedFromViewport()
    if not n.children.isNil:
        for c in n.children: c.nodeWillBeRemovedFromViewport()
    n.mViewport = nil

proc nodeWasAddedToViewport*(n: Node2D, v: Viewport) =
    n.mViewport = v
    if not n.components.isNil:
        for c in n.components.values: c.componentNodeWasAddedToViewport()
    if not n.children.isNil:
        for c in n.children: c.nodeWasAddedToViewport(v)

proc removeChild(n, child: Node2D) =
    for i, c in n.children:
        if c == child:
            n.children.delete(i)
            break

proc removeAllChildren*(n: Node2D) =
    for c in n.children:
        if not c.mViewport.isNil:
            c.nodeWillBeRemovedFromViewport()
        c.parent = nil
    n.children.setLen(0)

proc removeFromParent*(n: Node2D) =
    if not n.parent.isNil:
        if not n.mViewport.isNil:
            n.nodeWillBeRemovedFromViewport()

        n.parent.removeChild(n)
        n.parent = nil

proc addChild*(n, c: Node2D) =
    c.removeFromParent()
    n.children.safeAdd(c)
    c.parent = n
    if not n.mViewport.isNil:
        c.nodeWasAddedToViewport(n.mViewport)

proc newChild*(n: Node2D, childName: string = nil): Node2D =
    result = newNode(childName)
    n.addChild(result)

proc findNode*(n: Node2D, p: proc(n: Node2D): bool): Node2D =
    if p(n):
        result = n
    else:
        for c in n.children:
            result = c.findNode(p)
            if not result.isNil: break

proc findNode*(n: Node2D, name: string): Node2D =
    n.findNode proc(n: Node2D): bool =
        n.name == name

proc childNamed*(n: Node2D, name: string): Node2D =
    for c in n.children:
        if c.name == name: return c

proc visitProperties*(n: Node3D, p: var PropertyVisitor) =
    p.visitProperty("translation", n.translation)
    p.visitProperty("scale", n.scale)
    p.visitProperty("rotation", n.rotation)

proc visitComponentProperties*(n: Node3D, p: var PropertyVisitor) =
    if not n.components.isNil:
        for k, v in n.components:
            p.pushQualifier(k)
            v.visitProperties(p)
            p.popQualifier()

proc animatableProperty1*(n: Node2D, name: string): proc (val: Coord) =
    case name
    of "tX": result = proc (val: Coord) = n.translation.x = val
    of "tY": result = proc (val: Coord) = n.translation.y = val
    of "tZ": result = proc (val: Coord) = n.translation.z = val
    of "sX": result = proc (val: Coord) = n.scale.x = val
    of "sY": result = proc (val: Coord) = n.scale.y = val
    of "sZ": result = proc (val: Coord) = n.scale.z = val
    else:
        if not n.components.isNil:
            for k, v in n.components:
                result = v.animatableProperty1(name)
                if not result.isNil: break

    if result.isNil:
        raise newException(Exception, "Property " & name & " not found in node " & $n.name)
    doAssert(not result.isNil)

proc animatableProperty2*(n: Node2D, name: string): proc (val: Vector2) =
    case name
    of "translation": result = proc (val: Vector2) =
        n.translation.x = val.x
        n.translation.y = val.y
    of "scale": result = proc (val: Vector2) =
        n.scale.x = val.x
        n.scale.y = val.y
    else: doAssert(false)

proc animatableProperty3*(n: Node2D, name: string): proc (val: Vector3) =
    case name
    of "translation": result = proc (val: Vector3) =
        n.translation = val
    of "scale": result = proc (val: Vector3) =
        n.scale = val
    else: doAssert(false)

proc animatableProperty4*(n: Node2D, name: string): proc (val: Vector4) =
    case name
    of "rotation": result = proc (val: Vector4) =
        n.rotation = val
    else: doAssert(false)

proc translationFromMatrix(m: Matrix4): Vector3 = [m[12], m[13], m[14]]

proc worldTransform*(n: Node2D): Matrix4 =
    if n.parent.isNil:
        result = n.transform
    else:
        let w = n.parent.worldTransform
        w.multiply(n.transform, result)

proc localToWorld*(n: Node2D, p: Vector3): Vector3 =
    result = n.worldTransform * p

proc worldToLocal*(n: Node2D, p: Vector3): Vector3 =
    n.worldTransform.inversed() * p

proc reparentTo*(n, newParent: Node2D) =
    # Change parent of a node preserving its world transform
    let oldWorldTransform = n.worldTransform
    newParent.addChild(n)
    let newTransform = newParent.worldTransform.inversed() * oldWorldTransform
    n.translation = translationFromMatrix(newTransform)

proc animationNamed*(n: Node2D, name: string, preserveHandlers: bool = false): Animation =
    if not n.animations.isNil:
        result = n.animations.getOrDefault(name)
        if not result.isNil and not preserveHandlers: result.removeHandlers()

proc registerAnimation*(n: Node2D, name: string, a: Animation) =
    if n.animations.isNil:
        n.animations = newTable[string, Animation]()
    n.animations[name] = a

# Serialization
proc newNodeFromJson*(j: JsonNode): Node
proc deserialize*(n: Node, j: JsonNode)

proc loadComposition*(n: Node, compositionName: string) =
    loadJsonResourceAsync "compositions/" & compositionName & ".json", proc(j: JsonNode) =
        n.deserialize(j)

import ae_animation

proc deserialize*(n: Node, j: JsonNode) =
    if n.name.isNil:
        n.name = j["name"].getStr(nil)
    var v = j["translation"]
    if not v.isNil:
        n.translation = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    v = j["scale"]
    if not v.isNil:
        n.scale = newVector3(v[0].getFNum(), v[1].getFNum(), v[2].getFNum())
    v = j["rotation"]
    if not v.isNil:
        n.rotation = newQuaternion(v[0].getFNum(), v[1].getFNum(), v[2].getFNum(), v[3].getFNum())
    v = j["children"]
    if not v.isNil:
        for i in 0 ..< v.len:
            n.addChild(newNodeFromJson(v[i]))
    v = j["components"]
    if not v.isNil:
        for k, c in v:
            let comp = n.component(k)
            comp.deserialize(c)
    let animations = j["animations"]

    if not animations.isNil and animations.len > 0:
        n.animations = newTable[string, Animation]()
        for k, v in animations:
            n.animations[k] = animationWithAEJson(n, v)

    let compositionRef = j["compositionRef"].getStr(nil)
    if not compositionRef.isNil and not n.name.endsWith(".placeholder"):
        n.loadComposition(compositionRef)

proc newNodeFromJson*(j: JsonNode): Node =
    result = newNode()
    result.deserialize(j)

proc newNodeWithCompositionName*(name: string): Node =
    result = newNode(name)
    result.loadComposition(name)
