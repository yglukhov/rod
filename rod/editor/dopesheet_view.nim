import nimx.view, nimx.context
import nimx.view_event_handling_new

import animation_editor_types
import animation_chart_view

type DopesheetView* = ref object of AnimationChartView
    rowHeight*: Coord

method init*(v: DopesheetView, r: Rect) =
    procCall v.AnimationChartView.init(r)
    v.rowHeight = 20
    v.gridSize.height = 0

    var curve = newAnimationCurve()
    curve.addKey(0.0, 100)
    curve.addKey(0.5, 200)
    curve.addKey(1.0, 100)
    curve.color = newColor(1.0, 0, 0)
    v.curves.add(curve)

    curve = newAnimationCurve()
    curve.addKey(0.0, 150)
    curve.addKey(0.5, 250)
    curve.addKey(1.0, 150)
    curve.color = newColor(0.0, 1, 0)
    v.curves.add(curve)

proc curvePointToLocal(v: DopesheetView, p: Point): Point =
    result.x = (p.x - v.fromX) / (v.toX - v.fromX) * v.bounds.width
    result.y = p.y

proc localPointToCurve(v: DopesheetView, p: Point): Point =
    result.x = v.fromX + p.x / v.bounds.width * (v.toX - v.fromX)
    result.y = p.y

method draw*(v: DopesheetView, r: Rect) =
    procCall v.AnimationChartView.draw(r)
    let c = currentContext()
    v.drawGrid()

    c.strokeWidth = 0
    for i, curve in v.curves:
        c.fillColor = newColor(0, 0, 1)
        let rowMaxY = Coord(i + 1) * v.rowHeight + rulerHeight
        for k in curve.keys:
            var p = v.curvePointToLocal(k.point)
            p.y = rowMaxY - v.rowHeight / 2
            c.drawEllipseInRect(rectAtPoint(p, 4))
        c.fillColor = v.gridColor
        c.drawRect(newRect(0, rowMaxY, v.bounds.width, 1))

    v.drawTimeRuler()
    v.drawCursor()

method onTouchEv(v: DopesheetView, e: var Event): bool =
    discard procCall v.View.onTouchEv(e)
    if e.buttonState == bsDown:
        let pos = e.localPosition
        if pos.y < rulerHeight:
            v.mouseTrackingHandler = v.cursorTrackingHandler
        else:
            v.mouseTrackingHandler = proc(e: Event): bool =
                discard
    result = v.mouseTrackingHandler(e)
    if not result: v.mouseTrackingHandler = nil

method onScroll*(v: DopesheetView, e: var Event): bool =
    let cp = v.localPointToCurve(e.localPosition)
    let k = 1 + e.offset.y * 0.01
    v.fromX = cp.x - (cp.x - v.fromX) * k
    v.toX = cp.x + (v.toX - cp.x) * k
    v.setNeedsDisplay()
    result = true
