import nimx.view
import nimx.matrixes
import nimx.event
import nimx.view_event_handling
import nimx.system_logger
import rod.component
import rod.ray
import rod.viewport
import rod.rod_types
import rod.node

export UIComponent

type UICompView = ref object of View
    node: Node

proc intersectsWithUINode(r: Ray, n: Node, res: var Vector3): bool =
    let worldPointOnPlane = n.localToWorld(newVector3())
    var worldNormal = n.localToWorld(newVector3(0, 0, 1))
    worldNormal -= worldPointOnPlane
    worldNormal.normalize()
    r.intersectWithPlane(worldNormal, worldPointOnPlane, res)

method convertPointToParent*(v: UICompView, p: Point): Point =
    result = newPoint(-9999999, -9999999) # Some ridiculous value
    logi "WARNING: UICompView.convertPointToParent not implemented"

method convertPointFromParent*(v: UICompView, p: Point): Point =
    let r = v.node.sceneView.rayWithScreenCoords(p)
    var res : Vector3
    if r.intersectsWithUINode(v.node, res):
        res = v.node.worldToLocal(res)
        result = newPoint(res.x, res.y)
    else:
        result = newPoint(-9999999, -9999999) # Some ridiculous value

method draw*(c: UIComponent) =
    if not c.mView.isNil:
        c.mView.recursiveDrawSubviews()

proc `view=`*(c: UIComponent, v: View) =
    let cv = UICompView.new(newRect(0, 0, 20, 20))
    cv.window = c.node.sceneView.window
    cv.backgroundColor = clearColor()
    cv.node = c.node
    cv.superview = c.node.sceneView
    c.mView = cv
    cv.addSubview(v)

proc moveToWindow(v: View, w: Window) =
    v.window = w
    for s in v.subviews:
        s.moveToWindow(w)

proc handleMouseEvent*(c: UIComponent, r: Ray, e: var Event): bool =
    if not c.mView.isNil:
        var res : Vector3
        if r.intersectsWithUINode(c.node, res):
            if c.node.tryWorldToLocal(res, res):
                let v = c.mView.subviews[0]
                e.localPosition = v.convertPointFromParent(newPoint(res.x, res.y))
                result = v.recursiveHandleMouseEvent(e)

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
