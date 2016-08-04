import math, strutils
import nimx.view
import nimx.context
import nimx.view_event_handling_new
import nimx.font

import nimx.event, nimx.keyboard, nimx.window_event_handling

import nimx.editor.grid_drawing

import animation_editor_types
import animation_chart_view

type AnimationCurvesEditView* = ref object of AnimationChartView

method init*(v: AnimationCurvesEditView, r: Rect) =
    procCall v.AnimationChartView.init(r)

proc `*`(p: Point, c: Coord): Point = newPoint(p.x * c, p.y * c)

proc approximateLength(pts: openarray[Point]): Coord =
    for i in 0 ..< pts.len - 1:
        result += pts[i].distanceTo(pts[i + 1])

proc tesselationSegmentsForLength(length: Coord): int =
    const NoLessThan = 10;
    let segs = length/30.0
    return int(sqrt(segs * segs * 0.6 + NoLessThan * NoLessThan)) + 1

proc bezier4(pts: array[4, Point], t: Coord): Point =
    let nt = 1.0 - t
    let scalars = [nt*nt*nt, 3.0*nt*nt*t, 3.0*nt*t*t, t*t*t]
    for i in 0 ..< pts.len:
        result += pts[i] * scalars[i]

var tmpPoints = newSeq[Point]()

proc drawBezierCurve(c: GraphicsContext, points: array[4, Point]) =
    let nSegs = tesselationSegmentsForLength(approximateLength(points))
    tmpPoints.setLen(0)

    for n in 0 ..< nSegs:
        let i = n / (nSegs-1)
        tmpPoints.add(bezier4(points, i))

    for i in 0 ..< nSegs - 1:
        c.drawLine(tmpPoints[i], tmpPoints[i + 1])

import macros
macro dumpVars(args: varargs[typed]): stmt =
    result = newCall("echo")
    for a in args:
        result.add(newLit($a))
        result.add(newLit(": "))
        result.add(a)
        result.add(newLit(", "))

method draw(v: AnimationCurvesEditView, r: Rect) =
    procCall v.AnimationChartView.draw(r)
    let c = currentContext()
    v.drawGrid()

    c.strokeWidth = 1
    for curve in v.curves:
        for i in 0 ..< curve.keys.len - 1:
            let p1 = v.curvePointToLocal(newPoint(curve.keys[i].p, curve.keys[i].v))
            let p2 = v.curvePointToLocal(newPoint(curve.keys[i + 1].p, curve.keys[i + 1].v))

            let c1 = v.curvePointToLocal(curve.keys[i].outTangentAbs)
            let c2 = v.curvePointToLocal(curve.keys[i + 1].inTangentAbs)

            let points = [p1, c1, c2, p2]

            c.fillColor = newColor(1, 1, 0)
            c.strokeColor = newColor(1, 1, 0)

            c.strokeWidth = 1
            c.drawLine(p1, c1)
            c.drawLine(p2, c2)

            c.strokeWidth = 0
            c.drawEllipseInRect(rectAtPoint(c1, 4))
            c.drawEllipseInRect(rectAtPoint(c2, 4))

            c.strokeColor = curve.color
            c.fillColor = curve.color

            c.strokeWidth = 1
            c.drawBezierCurve(points)

            c.strokeWidth = 0
            c.drawRect(rectAtPoint(p1, 4))
            c.drawRect(rectAtPoint(p2, 4))

    v.drawTimeRuler()
    v.drawCursor()

proc getCurveAtPoint(v: AnimationCurvesEditView, p: Point, curve, key, tangent: var int) =
    for i, c in v.curves:
        curve = i
        for j, k in c.keys:
            key = j
            if p.inRect(rectAtPoint(v.curvePointToLocal(k.point), 4)):
                tangent = 0
                return
            elif p.inRect(rectAtPoint(v.curvePointToLocal(k.inTangentAbs), 4)):
                tangent = -1
                return
            elif p.inRect(rectAtPoint(v.curvePointToLocal(k.outTangentAbs), 4)):
                tangent = 1
                return
    curve = -1
    key = -1

proc curvePointTrackingHandler(v: AnimationCurvesEditView): proc(e: Event): bool =
    var draggedCurve, draggedKey, draggedTangent: int
    result = proc(e: Event): bool =
        case e.buttonState
        of bsDown:
            v.getCurveAtPoint(e.localPosition, draggedCurve, draggedKey, draggedTangent)
        of bsUnknown, bsUp:
            case draggedTangent
            of 0:
                var p = v.localPointToCurve(e.localPosition)
                p.x = round(p.x / v.gridSize.width) * v.gridSize.width
                v.curves[draggedCurve].keys[draggedKey].point = p
            of 1:
                v.curves[draggedCurve].keys[draggedKey].outTangent = v.localPointToCurve(e.localPosition) - v.curves[draggedCurve].keys[draggedKey].point
            else:
                v.curves[draggedCurve].keys[draggedKey].inTangent = v.localPointToCurve(e.localPosition) - v.curves[draggedCurve].keys[draggedKey].point
            if not v.onCursorPosChange.isNil: v.onCursorPosChange()
            v.setNeedsDisplay()
            if e.buttonState == bsUp:
                draggedCurve = -1
        result = draggedCurve != -1

method onTouchEv*(v: AnimationCurvesEditView, e: var Event): bool =
    if e.buttonState == bsDown:
        let pos = e.localPosition
        if pos.y < rulerHeight:
            v.mouseTrackingHandler = v.cursorTrackingHandler
        else:
            v.mouseTrackingHandler = v.curvePointTrackingHandler
    result = procCall v.AnimationChartView.onTouchEv(e)

method onScroll*(v: AnimationCurvesEditView, e: var Event): bool =
    when defined(macosx):
        let zoomByY = not (alsoPressed(VirtualKey.LeftGUI) or alsoPressed(VirtualKey.RightGUI))
    else:
        let zoomByY = not (alsoPressed(VirtualKey.LeftControl) or alsoPressed(VirtualKey.RightControl))
    let zoomByX = not (alsoPressed(VirtualKey.LeftShift) or alsoPressed(VirtualKey.RightShift))

    let cp = v.localPointToCurve(e.localPosition)
    let k = 1 + e.offset.y * 0.01
    if zoomByX:
        v.fromX = cp.x - (cp.x - v.fromX) * k
        v.toX = cp.x + (v.toX - cp.x) * k
    if zoomByY:
        v.fromY = cp.y - (cp.y - v.fromY) * k
        v.toY = cp.y + (v.toY - cp.y) * k

    v.setNeedsDisplay()
    result = true

registerClass(AnimationCurvesEditView)
