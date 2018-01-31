import math, strutils
import nimx / [ view, context, view_event_handling, font, keyboard,
        window_event_handling ]
import nimx.editor.grid_drawing

import animation_editor_types

const rulerHeight* = 25

type AnimationChartView* = ref object of View
    curves*: seq[AbstractAnimationCurve]
    fromX*, toX*: Coord
    fromY*, toY*: Coord
    cursorPos*: Coord
    gridSize*: Size
    gridColor*: Color
    sampleRate*: int
    mouseTrackingHandler*: proc(e: Event): bool
    onCursorPosChange*: proc()

method init*(v: AnimationChartView, r: Rect) =
    procCall v.View.init(r)
    v.toX = 1.0
    v.fromY = 300.0
    v.curves = @[]
    v.sampleRate = 30
    v.gridColor = newGrayColor(0.6, 1.0)
    v.gridSize = newSize(1.0 / float(v.sampleRate), 100)
    v.backgroundColor = newGrayColor(0.0, 0.2)

proc rectAtPoint*(p: Point, sz = 2.Coord): Rect =
    newRect(p.x - sz, p.y - sz, sz * 2, sz * 2)

proc curvePointToLocal*(v: AnimationChartView, p: Point): Point =
    result.x = (p.x - v.fromX) / (v.toX - v.fromX) * v.bounds.width
    result.y = (p.y - v.fromY) / (v.toY - v.fromY) * v.bounds.height

proc localPointToCurve*(v: AnimationChartView, p: Point): Point =
    result.x = v.fromX + p.x / v.bounds.width * (v.toX - v.fromX)
    result.y = v.fromY + p.y / v.bounds.height * (v.toY - v.fromY)

proc ceilTo[T](v, t: T): T =
    let vv = abs(v)
    let m = vv mod t
    result = vv + (t - m)
    if v < 0: result = -result

proc curveSizeToLocal*(v: AnimationChartView, s: Size): Size =
    result.width = s.width / (v.toX - v.fromX) * v.bounds.width
    result.height = s.height / (v.toY - v.fromY) * v.bounds.height

proc gridShift(v: AnimationChartView): Size =
    result.width = v.gridSize.width - v.fromX mod v.gridSize.width
    result.height = v.gridSize.height - v.fromY mod v.gridSize.height

proc localGridShift*(v: AnimationChartView): Size =
    v.curveSizeToLocal(v.gridShift)

proc localGridSize*(v: AnimationChartView): Size =
    v.curveSizeToLocal(v.gridSize)

proc drawTimeRuler*(v: AnimationChartView) =
    let c = currentContext()
    c.fillColor = newGrayColor(0.5, 0.5)
    c.drawRect(newRect(0, 0, v.bounds.width, rulerHeight))

    c.strokeWidth = 0

    #let labelWidth = 40.Coord

    let firstMarkPos = v.localGridShift.width
    let markInterval = v.localGridSize.width
    let marksCount = int((v.bounds.width - firstMarkPos) / markInterval)

    var frameNo = int((v.fromX + v.gridShift.width) * float(v.sampleRate))
    let f = systemFont()

    for i in 0 ..< marksCount:
        var x = firstMarkPos + Coord(i) * markInterval
        let s = $frameNo
        x -= f.sizeOfString(s).width / 2
        c.fillColor = newGrayColor(1.0, 0.5)
        var pt = newPoint(x, 0)
        c.drawText(f, pt, s)
        inc frameNo

    # let rulerWidth = v.bounds.width

    # let maxLabels = rulerWidth / labelWidth
    # let rulerRange = v.toX - v.fromX

    # let minRange = rulerRange * labelWidth / rulerWidth

    # let labelRange = ceilTo(minRange, 0.01)
    # let actualLabelWidth = labelRange / rulerRange * rulerWidth

    # let ticks = int(rulerWidth / actualLabelWidth)

    # var r = newRect(0, rulerHeight / 2, 1, rulerHeight / 2)
    # let f = systemFont()
    # for i in 0 ..< ticks:
    #     r.origin.x = Coord(i) * actualLabelWidth
    #     c.fillColor = newGrayColor(0.5, 0.5)
    #     c.drawRect(r)
    #     let s = formatFloat(v.fromX + labelRange * Coord(i), ffDecimal, 2)
    #     c.fillColor = newGrayColor(1.0, 0.5)
    #     var pt = newPoint(Coord(i) * actualLabelWidth - f.sizeOfString(s).width / 2, 0)
    #     c.drawText(f, pt, s)

proc drawGrid*(v: AnimationChartView) =
    let c = currentContext()
    c.fillColor = v.gridColor
    drawGrid(v.bounds, v.localGridSize, v.localGridShift)

proc drawCursor*(v: AnimationChartView) =
    if v.cursorPos >= v.fromX and v.cursorPos <= v.toX:
        let c = currentContext()
        c.fillColor = newColor(1, 0, 0)
        c.strokeWidth = 0
        let p = v.curvePointToLocal(newPoint(v.cursorPos, 0))
        c.drawRect(newRect(p.x, 0, 1, v.bounds.height))

proc cursorTrackingHandler*(v: AnimationChartView): proc(e: Event): bool =
    result = proc(e: Event): bool =
        v.cursorPos = v.localPointToCurve(e.localPosition).x
        # Snap to grid
        v.cursorPos = round(v.cursorPos / v.gridSize.width) * v.gridSize.width

        if not v.onCursorPosChange.isNil:
            v.onCursorPosChange()
        v.setNeedsDisplay()
        result = e.buttonState != bsUp

method onTouchEv*(v: AnimationChartView, e: var Event): bool =
    result = procCall v.View.onTouchEv(e)
    if not v.mouseTrackingHandler.isNil:
        if v.mouseTrackingHandler(e):
            result = true
        else:
            v.mouseTrackingHandler = nil

proc processZoomEvent*(v: AnimationChartView, e: var Event, allowZoomX, allowZoomY: bool) =
    when defined(macosx):
        let zoomByY = not e.modifiers.anyGui()
    else:
        let zoomByY = not e.modifiers.anyCtrl()
    let zoomByX = not e.modifiers.anyShift()

    let cp = v.localPointToCurve(e.localPosition)
    let k = 1 + e.offset.y * 0.01
    if zoomByX and allowZoomX:
        v.fromX = cp.x - (cp.x - v.fromX) * k
        v.toX = cp.x + (v.toX - cp.x) * k
        if v.fromX < 0:
            v.toX += -v.fromX
            v.fromX = 0
    if zoomByY and allowZoomY:
        v.fromY = cp.y - (cp.y - v.fromY) * k
        v.toY = cp.y + (v.toY - cp.y) * k

    v.setNeedsDisplay()
