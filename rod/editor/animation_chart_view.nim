import math, strutils
import nimx.view
import nimx.context
import nimx.view_event_handling_new
import nimx.font

import nimx.event, nimx.keyboard, nimx.window_event_handling

import nimx.editor.grid_drawing

import animation_editor_types

const rulerHeight* = 25

type AnimationChartView* = ref object of View
    curves*: seq[AnimationCurve]
    fromX*, toX*: Coord
    fromY*, toY*: Coord
    cursorPos*: Coord
    gridSize*: Size
    gridColor*: Color
    mouseTrackingHandler*: proc(e: Event): bool

method init*(v: AnimationChartView, r: Rect) =
    procCall v.View.init(r)
    v.toX = 1.0
    v.toY = 300.0
    v.curves = @[]
    v.gridColor = newGrayColor(0.6, 1.0)
    v.gridSize = newSize(0.25, 100)
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

proc drawTimeRuler*(v: AnimationChartView) =
    let c = currentContext()
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

proc drawGrid*(v: AnimationChartView) =
    let c = currentContext()
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

proc drawCursor*(v: AnimationChartView) =
    let c = currentContext()
    c.fillColor = newColor(1, 0, 0)
    c.strokeWidth = 0
    let p = v.curvePointToLocal(newPoint(v.cursorPos, 0))
    c.drawRect(newRect(p.x, 0, 1, v.bounds.height))

proc cursorTrackingHandler*(v: AnimationChartView): proc(e: Event): bool =
    result = proc(e: Event): bool =
        v.cursorPos = v.localPointToCurve(e.localPosition).x
        v.setNeedsDisplay()
        result = e.buttonState != bsUp

method onScroll*(v: AnimationChartView, e: var Event): bool =
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
