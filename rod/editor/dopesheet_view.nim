import nimx.view, nimx.context
import nimx.view_event_handling_new

import animation_editor_types
import animation_chart_view

type DopesheetView* = ref object of AnimationChartView
    rowHeight*: Coord
    selectedCurve: int
    selectedKey: int

method init*(v: DopesheetView, r: Rect) =
    procCall v.AnimationChartView.init(r)
    v.rowHeight = 20
    v.gridSize.height = 0

proc curvePointToLocal(v: DopesheetView, p: Point): Point =
    result.x = (p.x - v.fromX) / (v.toX - v.fromX) * v.bounds.width
    result.y = p.y

proc localPointToCurve(v: DopesheetView, p: Point): Point =
    result.x = v.fromX + p.x / v.bounds.width * (v.toX - v.fromX)
    result.y = p.y

proc rowMaxY(v: DopesheetView, row: int): Coord = Coord(row + 1) * v.rowHeight + rulerHeight

method draw*(v: DopesheetView, r: Rect) =
    procCall v.AnimationChartView.draw(r)
    let c = currentContext()
    v.drawGrid()

    c.strokeWidth = 0
    for i, curve in v.curves:
        let rowMaxY = v.rowMaxY(i)
        for j, k in curve.keys:
            var p = v.curvePointToLocal(k.point)
            p.y = rowMaxY - v.rowHeight / 2
            if i == v.selectedCurve and j == v.selectedKey:
                c.fillColor = newColor(0.7, 0.7, 1)
            else:
                c.fillColor = newGrayColor(0.5)
            c.drawEllipseInRect(rectAtPoint(p, 4))
        c.fillColor = v.gridColor
        c.drawRect(newRect(0, rowMaxY, v.bounds.width, 1))

    v.drawTimeRuler()
    v.drawCursor()

proc dopesheetSelectionTrackingHandler(v: DopesheetView): proc(e: Event): bool =
    result = proc(e: Event): bool =
        for i, curve in v.curves:
            let rowMaxY = v.rowMaxY(i)
            for j, k in curve.keys:
                var p = v.curvePointToLocal(k.point)
                p.y = rowMaxY - v.rowHeight / 2
                if e.localPosition.inRect(rectAtPoint(p, 4)):
                    v.selectedCurve = i
                    v.selectedKey = j
                    break

method onTouchEv*(v: DopesheetView, e: var Event): bool =
    if e.buttonState == bsDown:
        let pos = e.localPosition
        if pos.y < rulerHeight:
            v.mouseTrackingHandler = v.cursorTrackingHandler
        else:
            v.mouseTrackingHandler = v.dopesheetSelectionTrackingHandler
    result = procCall v.AnimationChartView.onTouchEv(e)

method onScroll*(v: DopesheetView, e: var Event): bool =
    let cp = v.localPointToCurve(e.localPosition)
    let k = 1 + e.offset.y * 0.01
    v.fromX = cp.x - (cp.x - v.fromX) * k
    v.toX = cp.x + (v.toX - cp.x) * k
    v.setNeedsDisplay()
    result = true

method acceptsFirstResponder*(v: DopesheetView): bool = true

method onKeyDown*(v: DopesheetView, e: var Event): bool =
    if e.keyCode == VirtualKey.Delete:
        if v.selectedCurve < v.curves.len and v.selectedKey < v.curves[v.selectedCurve].keys.len:
            v.curves[v.selectedCurve].keys.delete(v.selectedKey)
            v.setNeedsDisplay()
            result = true

registerClass(DopesheetView)
