import math, strutils
import nimx.view
import nimx.context
import nimx.view_event_handling_new
import nimx.font

import nimx.event, nimx.keyboard, nimx.window_event_handling

import nimx.editor.grid_drawing

type
    KeyFrame = object
        p: float
        v: float
        inTangent: Point
        outTangent: Point

    AnimationCurve* = ref object
        keys: seq[KeyFrame]
        color*: Color

    AnimationCurvesEditView* = ref object of View
        curves: seq[AnimationCurve]
        fromX, toX: Coord
        fromY, toY: Coord
        draggedCurve, draggedKey, draggedTangent: int
        gridSize: Size
        gridColor: Color

proc point(k: KeyFrame): Point = newPoint(k.p, k.v)
proc inTangentAbs(k: KeyFrame): Point = k.point + k.inTangent
proc outTangentAbs(k: KeyFrame): Point = k.point + k.outTangent

proc `point=`(k: var KeyFrame, p: Point) =
    k.p = p.x
    k.v = p.y

proc newAnimationCurve*(): AnimationCurve =
    result.new()
    result.keys = @[]

proc addKey*(c: AnimationCurve, p, v: float) =
    var k: KeyFrame
    k.p = p
    k.v = v
    k.inTangent = newPoint(-0.5, 50)
    k.outTangent = newPoint(0.5, -50)
    c.keys.add(k)

method init*(v: AnimationCurvesEditView, r: Rect) =
    procCall v.View.init(r)
    v.toX = 1.0
    v.toY = 300.0
    v.curves = @[]
    v.gridColor = newGrayColor(0.6, 1.0)

    v.gridSize = newSize(0.25, 100)

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

    v.backgroundColor = newGrayColor(0.0, 0.2)

proc rectAtPoint(p: Point, sz = 2.Coord): Rect =
    newRect(p.x - sz, p.y - sz, sz * 2, sz * 2)

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

proc curvePointToLocal(v: AnimationCurvesEditView, p: Point): Point =
    result.x = (p.x - v.fromX) / (v.toX - v.fromX) * v.bounds.width
    result.y = (p.y - v.fromY) / (v.toY - v.fromY) * v.bounds.height

proc localPointToCurve(v: AnimationCurvesEditView, p: Point): Point =
    result.x = v.fromX + p.x / v.bounds.width * (v.toX - v.fromX)
    result.y = v.fromY + p.y / v.bounds.height * (v.toY - v.fromY)

proc ceilTo[T](v, t: T): T =
    let vv = abs(v)
    let m = vv mod t
    result = vv + (t - m)
    if v < 0: result = -result

import macros
macro dumpVars(args: varargs[typed]): stmt =
    result = newCall("echo")
    for a in args:
        result.add(newLit($a))
        result.add(newLit(": "))
        result.add(a)
        result.add(newLit(", "))

proc drawTimeRuler(v: AnimationCurvesEditView) =
    let c = currentContext()
    const rulerHeight = 30
    c.fillColor = newGrayColor(0.5, 0.5)
    c.drawRect(newRect(0, 0, v.bounds.width, rulerHeight))

    c.strokeWidth = 0

    let rulerWidth = v.bounds.width
    let labelWidth = 40.Coord

    let maxLabels = rulerWidth / labelWidth
    let rulerRange = v.toX - v.fromX

    let minRange = rulerRange * labelWidth / rulerWidth

    let labelRange = ceilTo(minRange, 0.01)
    let actualLabelWidth = labelRange / rulerRange * rulerWidth

    let ticks = int(rulerWidth / actualLabelWidth)

    var r = newRect(0, rulerHeight / 2, 1, rulerHeight / 2)
    let f = systemFont()
    for i in 0 ..< ticks:
        r.origin.x = Coord(i) * actualLabelWidth
        c.fillColor = newGrayColor(0.5, 0.5)
        c.drawRect(r)
        let s = formatFloat(v.fromX + labelRange * Coord(i), ffDecimal, 2)
        c.fillColor = blackColor()
        var pt = newPoint(Coord(i) * actualLabelWidth - f.sizeOfString(s).width / 2, 0)
        c.drawText(f, pt, s)

method draw(v: AnimationCurvesEditView, r: Rect) =
    procCall v.View.draw(r)
    let c = currentContext()

    block: # Draw grid:
        c.fillColor = v.gridColor
        var gs = v.gridSize
        let kx = (v.toX - v.fromX) / v.bounds.width
        let ky = (v.toY - v.fromY) / v.bounds.height
        gs.width /= kx
        gs.height /= ky
        var gridShift : Size
        gridShift.width = (v.gridSize.width - v.fromX mod v.gridSize.width) / kx
        gridShift.height = (v.gridSize.height - v.fromY mod v.gridSize.height) / ky
        drawGrid(v.bounds, gs, gridShift)

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

method onTouchEv(v: AnimationCurvesEditView, e: var Event): bool =
    discard procCall v.View.onTouchEv(e)
    case e.buttonState
    of bsDown:
        v.getCurveAtPoint(e.localPosition, v.draggedCurve, v.draggedKey, v.draggedTangent)
    of bsUnknown, bsUp:
        case v.draggedTangent
        of 0:
            v.curves[v.draggedCurve].keys[v.draggedKey].point = v.localPointToCurve(e.localPosition)
        of 1:
            v.curves[v.draggedCurve].keys[v.draggedKey].outTangent = v.localPointToCurve(e.localPosition) - v.curves[v.draggedCurve].keys[v.draggedKey].point
        else:
            v.curves[v.draggedCurve].keys[v.draggedKey].inTangent = v.localPointToCurve(e.localPosition) - v.curves[v.draggedCurve].keys[v.draggedKey].point
        v.setNeedsDisplay()
        if e.buttonState == bsUp:
            v.draggedCurve = -1
    result = v.draggedCurve != -1

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
