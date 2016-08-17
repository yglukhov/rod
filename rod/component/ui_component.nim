import nimx.view
import nimx.matrixes
import nimx.event
import nimx.view_event_handling
import nimx.view_event_handling_new
import nimx.system_logger
import rod.component
import rod.ray
import rod.viewport
import rod.rod_types
import rod.node
export UIComponent

type UICompView = ref object of View
    uiComp: UIComponent

proc view*(c: UIComponent): View =
    if not c.mView.isNil:
        result = c.mView.subviews[0]

proc intersectsWithUINode*(uiComp: UIComponent, r: Ray, res: var Vector3): bool =
    let n = uiComp.node
    let worldPointOnPlane = n.localToWorld(newVector3())
    var worldNormal = n.localToWorld(newVector3(0, 0, 1))
    worldNormal -= worldPointOnPlane
    worldNormal.normalize()
    result = r.intersectWithPlane(worldNormal, worldPointOnPlane, res)

    if result and not uiComp.mView.isNil:
        let v = uiComp.view
        if not v.isNil:
            var localres : Vector3
            if n.tryWorldToLocal(res, localres):
                result = localres.x >= v.frame.x and localres.x <= v.frame.maxX and
                    localres.y >= v.frame.y and localres.y <= v.frame.maxY

method convertPointToParent*(v: UICompView, p: Point): Point =
    result = newPoint(-9999999, -9999999) # Some ridiculous value
    logi "WARNING: UICompView.convertPointToParent not implemented"

method convertPointFromParent*(v: UICompView, p: Point): Point =
    result = newPoint(-9999999, -9999999) # Some ridiculous value
    if not v.uiComp.node.sceneView.isNil:
        let r = v.uiComp.node.sceneView.rayWithScreenCoords(p)
        var res : Vector3
        if v.uiComp.intersectsWithUINode(r, res):
            if v.uiComp.node.tryWorldToLocal(res, res):
                result = newPoint(res.x, res.y)

method draw*(c: UIComponent) =
    if not c.mView.isNil:
        c.mView.recursiveDrawSubviews()

proc `view=`*(c: UIComponent, v: View) =
    let cv = UICompView.new(newRect(0, 0, 20, 20))
    cv.window = c.node.sceneView.window
    cv.backgroundColor = clearColor()
    cv.uiComp = c
    cv.superview = c.node.sceneView
    c.mView = cv
    cv.addSubview(v)

proc moveToWindow(v: View, w: Window) =
    v.window = w
    for s in v.subviews:
        s.moveToWindow(w)

proc handleMouseEvent*(c: UIComponent, r: Ray, e: var Event, intersection: Vector3): bool =
    var res : Vector3
    if c.node.tryWorldToLocal(intersection, res):
        let v = c.view
        e.localPosition = v.convertPointFromParent(newPoint(res.x, res.y))
        result = v.recursiveHandleMouseEvent(e)

proc handleTouchEv*(c: UIComponent, r: Ray, e: var Event, intersection: Vector3): bool =
    var res : Vector3
    if c.node.tryWorldToLocal(intersection, res):
        let v = c.view
        e.localPosition = v.convertPointFromParent(newPoint(res.x, res.y))
        if e.localPosition.inRect(v.bounds):
            result = v.processTouchEvent(e)
            if result and e.buttonState == bsDown:
                c.mView.touchTarget = v

proc sceneViewWillMoveToWindow*(c: UIComponent, w: Window) =
    if not c.mView.isNil:
        c.mView.viewWillMoveToWindow(w)
        c.mView.moveToWindow(w)

method componentNodeWasAddedToSceneView*(ui: UIComponent) =
    let sv = ui.node.sceneView
    if sv.uiComponents.isNil:
        sv.uiComponents = @[ui]
    else:
        sv.uiComponents.add(ui)

method componentNodeWillBeRemovedFromSceneView(ui: UIComponent) =
    let sv = ui.node.sceneView
    if not sv.uiComponents.isNil:
        let i = sv.uiComponents.find(ui)
        if i != -1:
            sv.uiComponents.del(i)

registerComponent[UIComponent]()
