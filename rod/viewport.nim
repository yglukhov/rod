import nimx / [ context, types, image, portable_gl, window,
                view, view_event_handling, animation ]

import algorithm, logging, times, tables, strutils
import rod / component / camera
import rod / [ component, systems, node, ray, rod_types ]

export SceneView

var deltaTime = 0.0
var oldTime = 0.0

proc getSystem*(v: SceneView, T: typedesc[System]): T =
    for s in v.systems:
        if s of T:
            return s.T
    return nil

proc addSystem*(v: SceneView, T: typedesc[System]): T =
    result = createSystem(T).T
    result.sceneView = v
    v.systems.add(result)

proc system*(v: SceneView, T: typedesc[System]): T =
    result = v.getSystem(T)
    if result.isNil:
        result = v.addSystem(T)

proc getDeltaTime*(): float =
    return deltaTime

proc `camera=`*(v: SceneView, c: Camera) =
    v.mCamera = c

template rootNode*(v: SceneView): Node = v.mRootNode

proc `rootNode=`*(v: SceneView, n: Node) =
    if not v.mRootNode.isNil:
        v.mRootNode.nodeWillBeRemovedFromSceneView()
    v.mRootNode = n
    if not n.isNil:
        n.nodeWasAddedToSceneView(v)

proc camera*(v: SceneView): Camera =
    if v.mCamera.isNil:
        let nodeWithCamera = v.rootNode.findNode(proc (n: Node): bool = not n.componentIfAvailable(Camera).isNil)
        if not nodeWithCamera.isNil:
            v.mCamera = nodeWithCamera.componentIfAvailable(Camera)
    result = v.mCamera

template viewMatrix*(v: SceneView): Matrix4 = v.mCamera.node.worldTransform.inversed

proc getProjectionMatrix*(v: SceneView): Matrix4 =
    v.camera.getProjectionMatrix(v.bounds, result)

proc getViewProjectionMatrix*(v: SceneView): Matrix4 =
    let cam = v.camera
    doAssert(not cam.isNil)
    v.viewMatrixCached = v.viewMatrix
    var projTransform : Transform3D
    cam.getProjectionMatrix(v.bounds, projTransform)
    result = projTransform * v.viewMatrixCached

proc worldToScreenPoint*(v: SceneView, point: Vector3): Vector3 =
    let absBounds = v.convertRectToWindow(v.bounds)
    let clipSpacePos = v.viewProjMatrix * newVector4(point.x, point.y, point.z, 1.0)
    var ndcSpacePos: Vector3
    if clipSpacePos[3] > 0:
        ndcSpacePos = newVector3(clipSpacePos[0] / clipSpacePos[3], clipSpacePos[1] / clipSpacePos[3], clipSpacePos[2] / clipSpacePos[3])
    else:
        ndcSpacePos = newVector3(clipSpacePos[0], clipSpacePos[1], clipSpacePos[2])

    let b = if v.window.isNil: v.bounds else: v.window.bounds

    result.x = ((ndcSpacePos.x + 1.0) / 2.0) * b.width - absBounds.x
    result.y = ((1.0 - ndcSpacePos.y) / 2.0) * b.height - absBounds.y
    result.z = (1.0 + ndcSpacePos.z) * 0.5

proc screenToWorldPoint*(v: SceneView, point: Vector3): Vector3 =
    let absBounds = v.convertRectToWindow(v.bounds)
    var winSize = absBounds.size

    if not v.window.isNil:
        winSize = v.window.bounds.size

    let matViewProj = v.viewProjMatrix
    var matInverse: Matrix4
    if tryInverse(matViewProj, matInverse) == false:
        return

    var oIn: Vector4
    oIn[0] = (point.x + absBounds.x) / winSize.width * 2.0 - 1.0
    oIn[1] = 1.0 - (point.y + absBounds.y) / winSize.height * 2.0
    oIn[2] = 2.0 * point.z - 1.0
    oIn[3] = 1.0

    let vIn = newVector4(oIn[0], oIn[1], oIn[2], oIn[3])
    var pos = matInverse * vIn
    pos[3] = 1.0 / pos[3]

    result.x = pos.x * pos[3]
    result.y = pos.y * pos[3]
    result.z = pos.z * pos[3]

template getViewMatrix*(v: SceneView): Matrix4 {.deprecated.} = v.getViewProjectionMatrix()

import tables

proc update(v: SceneView, dt: float) =
    if not v.rootNode.isNil:
        v.rootNode.recursiveUpdate(dt)
    for s in v.systems:
        s.update(dt)

method draw*(v: SceneView, r: Rect) =
    procCall v.View.draw(r)

    for s in v.systems:
        s.draw()

    if v.rootNode.isNil: return
    let c = currentContext()

    v.viewProjMatrix = v.getViewProjectionMatrix()
    c.withTransform v.viewProjMatrix:
        v.rootNode.recursiveDraw()

        if not v.afterDrawProc.isNil:
            v.afterDrawProc()

proc rayWithScreenCoords*(v: SceneView, coords: Point): Ray =
    if v.camera.projectionMode == cpOrtho:
        var logicalWidth = v.bounds.width / (v.bounds.height / v.camera.viewportSize.height)
        var viewCoords:Vector3
        viewCoords.x = coords.x / v.bounds.width * logicalWidth - logicalWidth / 2.0
        viewCoords.y = coords.y / v.bounds.height * v.camera.viewportSize.height - v.camera.viewportSize.height / 2.0
        viewCoords.z = 10.0

        result.origin = v.camera.node.worldTransform * viewCoords
        let dirPoint = v.camera.node.worldTransform * newVector3(viewCoords.x, viewCoords.y, -1.0)

        result.direction = dirPoint - result.origin
        result.direction.normalize()
        return

    result.origin = v.camera.node.worldPos() #v.camera.node.localToWorld(newVector3())
    let target = v.screenToWorldPoint(newVector3(coords.x, coords.y, -1))
    result.direction = target - result.origin
    result.direction.normalize()

proc rayCastFirstNode*(v: SceneView, node: Node, coords: Point): Node =
    let r = v.rayWithScreenCoords(coords)
    var castResult = newSeq[RayCastInfo]()
    node.rayCast(r, castResult)

    if castResult.len > 0:
        castResult.sort do(x, y: RayCastInfo) -> int:
            result = -cmp(x.distance, y.distance)

        # for i in countdown(castResult.len - 1, 0):
        #     if castResult[i].node.isEnabledInTree:
        #         return castResult[i].node

        result = castResult[^1].node

proc addAnimation*(v: SceneView, a: Animation) = v.animationRunners[0].pushAnimation(a)

proc removeAnimation*(v: SceneView, a: Animation) = v.animationRunners[0].removeAnimation(a)

proc addAnimationRunner*(v: SceneView, ar: AnimationRunner) =
    if ar notin v.animationRunners:
        v.animationRunners.add(ar)

        if not v.window.isNil:
            v.window.addAnimationRunner(ar)

proc removeAnimationRunner*(v: SceneView, ar: AnimationRunner) =
    if (let idx = v.animationRunners.find(ar); idx != -1):
        v.animationRunners.del(idx)

        if not v.window.isNil:
            v.window.removeAnimationRunner(ar)

import component/ui_component, algorithm

method name*(v: SceneView): string =
    result = "SceneView"

type UIComponentIntersection* = tuple[i: Vector3, c: UIComponent]

proc getUiComponentsIntersectingWithRay*(v: SceneView, r: Ray): seq[UIComponentIntersection] =
    result = @[]
    for c in v.uiComponents:
        var inter : Vector3
        if c.enabled and c.node.isEnabledInTree and c.intersectsWithUINode(r, inter):
            result.add((inter, c))

    template dist(a, b): auto = (a - b).length
    if result.len > 1:
        result.sort() do(x, y: UIComponentIntersection) -> int:
            result = int((dist(x.i, r.origin) - dist(y.i, r.origin)) * 5)
            if result == 0:
                result = getTreeDistance(x.c.node, y.c.node)

method onScroll*(v: SceneView, e: var Event): bool =
    if v.uiComponents.len > 0:
        let r = v.rayWithScreenCoords(e.localPosition)
        let intersections = v.getUiComponentsIntersectingWithRay(r)
        if intersections.len > 0:
            for i in intersections:
                result = i.c.handleScrollEv(r, e, i.i)
                if result:
                    v.touchTarget = i.c.mView
                    break

    if not result:
        result = procCall v.View.onScroll(e)

method onTouchEv*(v: SceneView, e: var Event): bool =
    let target = v.window.mCurrentTouches.getOrDefault(e.pointerId)
    if v.uiComponents.len > 0 and target != v:
        if e.buttonState == bsDown:
            let r = v.rayWithScreenCoords(e.localPosition)
            let intersections = v.getUiComponentsIntersectingWithRay(r)
            if intersections.len > 0:
                for i in intersections:
                    result = i.c.handleTouchEv(r, e, i.i)
                    if result:
                        v.touchTarget = i.c.mView
                        break
        else:
            if not v.touchTarget.isNil:
                let target = v.touchTarget
                var localPosition = e.localPosition
                e.localPosition = target.convertPointFromParent(localPosition)
                result = target.processTouchEvent(e)
                e.localPosition = localPosition

    if not result:
        result = procCall v.View.onTouchEv(e)

method viewOnEnter*(v:SceneView){.base.} = discard
method viewOnExit*(v:SceneView){.base.} = discard

method viewDidMoveToWindow*(v:SceneView)=
    procCall v.View.viewDidMoveToWindow()
    if not v.editing and not v.window.isNil:
        v.viewOnEnter()

    for ar in v.animationRunners:
        v.window.addAnimationRunner(ar)

method viewWillMoveToWindow*(v: SceneView, w: Window) =
    if not v.editing and w.isNil:
        v.viewOnExit()

    if not v.window.isNil:
        for ar in v.animationRunners:
            v.window.removeAnimationRunner(ar)

    procCall v.View.viewWillMoveToWindow(w)
    for c in v.uiComponents:
        c.sceneViewWillMoveToWindow(w)

method init*(v: SceneView, frame: Rect) =
    procCall v.View.init(frame)
    v.addAnimationRunner(newAnimationRunner())

    v.world = new(World)
    var updateAnim = newAnimation()
    updateAnim.tag = "deltaTimeAnimation"
    updateAnim.numberOfLoops = -1
    updateAnim.loopDuration = 1.0
    updateAnim.onAnimate = proc(p: float) =
        deltaTime = updateAnim.curLoop.float + p - oldTime
        oldTime = updateAnim.curLoop.float + p
        if deltaTime < 0.0001:
            deltaTime = 0.0001
        v.update(deltaTime)
    v.addAnimation(updateAnim)

method resizeSubviews*(v: SceneView, oldSize: Size) =
    procCall v.View.resizeSubviews(oldSize)
    v.viewProjMatrix = v.getViewProjectionMatrix()

import component/all_components
