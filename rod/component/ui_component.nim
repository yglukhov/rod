import nimx / [ view, matrixes, view_event_handling, property_visitor ]
import rod / [ component, ray, viewport, node, rod_types ]
import logging
export UIComponent

type UICompView = ref object of View
    uiComp: UIComponent
    uiCompSubview: View

method `enabled=`*(c: UIComponent, state: bool) {.base.}=
    c.mEnabled = state

proc enabled*(c: UIComponent): bool =
    result = c.mEnabled

proc view*(c: UIComponent): View =
    if not c.mView.isNil:
        result = c.mView.UICompView.uiCompSubview

proc intersectsWithUIPlane(uiComp: UIComponent, r: Ray, res: var Vector3): bool=
    let n = uiComp.node
    let worldPointOnPlane = n.localToWorld(newVector3())
    var worldNormal = n.localToWorld(newVector3(0, 0, 1))
    worldNormal -= worldPointOnPlane
    worldNormal.normalize()
    result = r.intersectWithPlane(worldNormal, worldPointOnPlane, res)

proc intersectsWithUINode*(uiComp: UIComponent, r: Ray, res: var Vector3): bool =
    if uiComp.intersectsWithUIPlane(r, res) and not uiComp.mView.isNil:
        let v = uiComp.view
        if not v.isNil:
            var localres : Vector3
            if uiComp.node.tryWorldToLocal(res, localres):
                result = localres.x >= v.frame.x and localres.x <= v.frame.maxX and
                    localres.y >= v.frame.y and localres.y <= v.frame.maxY

method convertPointToParent*(v: UICompView, p: Point): Point =
    result = newPoint(-9999999, -9999999) # Some ridiculous value
    warn "UICompView.convertPointToParent not implemented"

method convertPointFromParent*(v: UICompView, p: Point): Point =
    result = newPoint(-9999999, -9999999) # Some ridiculous value
    if not v.uiComp.node.sceneView.isNil:
        let r = v.uiComp.node.sceneView.rayWithScreenCoords(p)
        var res : Vector3
        if v.uiComp.intersectsWithUIPlane(r, res):
            if v.uiComp.node.tryWorldToLocal(res, res):
                result = newPoint(res.x, res.y)

method draw*(c: UIComponent) =
    if not c.mView.isNil:
        c.mView.recursiveDrawSubviews()

proc updSuperview(c: UIComponent) =
    if not c.mView.isNil and not c.node.sceneView.isNil:
        c.mView.superview = c.node.sceneView
        c.mView.window = c.node.sceneView.window
        c.mView.addSubview(c.mView.UICompView.uiCompSubview)

proc `view=`*(c: UIComponent, v: View) =
    if not c.view.isNil:
        c.view.removeFromSuperview()

    if v == nil:
        c.mView = nil
        return

    let cv = UICompView.new(newRect(0, 0, 20, 20))
    cv.uiComp = c
    c.mView = cv
    c.enabled = true
    cv.uiCompSubview = v
    c.updSuperview()

proc moveToWindow(v: View, w: Window) =
    v.window = w
    for s in v.subviews:
        s.moveToWindow(w)

proc handleScrollEv*(c: UIComponent, r: Ray, e: var Event, intersection: Vector3): bool =
    var res : Vector3
    if c.node.tryWorldToLocal(intersection, res):
        let v = c.view
        let tmpLocalPosition = e.localPosition
        e.localPosition = v.convertPointFromParent(newPoint(res.x, res.y))
        if e.localPosition.inRect(v.bounds):
            result = v.processMouseWheelEvent(e)

        e.localPosition = tmpLocalPosition

proc handleTouchEv*(c: UIComponent, r: Ray, e: var Event, intersection: Vector3): bool =
    var res : Vector3
    if c.node.tryWorldToLocal(intersection, res):
        let v = c.view
        let tmpLocalPosition = e.localPosition
        e.localPosition = v.convertPointFromParent(newPoint(res.x, res.y))
        if e.localPosition.inRect(v.bounds):
            result = v.processTouchEvent(e)
            if result and e.buttonState == bsDown:
                c.mView.touchTarget = v

        e.localPosition = tmpLocalPosition

proc sceneViewWillMoveToWindow*(c: UIComponent, w: Window) =
    if not c.mView.isNil:
        c.mView.viewWillMoveToWindow(w)
        c.mView.moveToWindow(w)

method componentNodeWasAddedToSceneView*(ui: UIComponent) =
    let sv = ui.node.sceneView
    sv.uiComponents.add(ui)

    ui.updSuperview()

method componentNodeWillBeRemovedFromSceneView(ui: UIComponent) =
    let sv = ui.node.sceneView
    let i = sv.uiComponents.find(ui)
    if i != -1:
        sv.uiComponents.del(i)

    if not ui.view.isNil:
        ui.view.removeFromSuperview()

method visitProperties*(ui: UIComponent, p: var PropertyVisitor) =
    p.visitProperty("enabled", ui.enabled)
    ui.view.visitProperties(p)

registerComponent(UIComponent)
