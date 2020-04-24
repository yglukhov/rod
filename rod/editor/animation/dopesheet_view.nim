import nimx / [ view, context, view_event_handling ]
import animation_editor_types, animation_chart_view
import math, sets, sequtils

type
    DopesheetSelectedKey* = tuple
        pi,ki: int

    DopesheetView* = ref object of AnimationChartView
        editedAnimation*: EditedAnimation
        selectionRect: Rect
        selectionOrigin: Point
        rowHeight*: Coord
        mSelectedKeys: HashSet[DopesheetSelectedKey]
        selectedKeysWasChanged: bool
        draggedKey: DopesheetSelectedKey
        selectedCurve*: int
        selectedKey*: int
        onKeysChanged*: proc(keys: seq[DopesheetSelectedKey])
        onKeysSelected*: proc(keys: seq[DopesheetSelectedKey])

proc selectedKeys*(v: DopesheetView): seq[DopesheetSelectedKey] =
    result = toSeq(v.mSelectedKeys)

proc clearSelection*(v: DopesheetView) =
    v.mSelectedKeys.clear()

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

const selectionColor = newColor(0.0, 0.0, 0.5, 0.2)

method draw*(v: DopesheetView, r: Rect) =
    procCall v.AnimationChartView.draw(r)
    let c = currentContext()
    v.drawGrid()

    let dimension = 0

    c.strokeWidth = 0
    if not v.editedAnimation.isNil:
        for y, p in v.editedAnimation.properties:
            let rowMaxY = v.rowMaxY(y)
            for x, key in p.keys:
                if key.position > v.toX: break
                elif key.position >= v.fromX:
                    var pos = v.curvePointToLocal(newPoint(key.position, 0.0))
                    pos.y = rowMaxY - v.rowHeight / 2
                    # if i == v.
                    # if y == v.selectedCurve and x == v.selectedKey:
                    if (pi:y, ki:x) in v.selectedKeys:
                        c.fillColor = newColor(0.7, 0.7, 1)
                    else:
                        c.fillColor = newGrayColor(0.5)
                    c.drawEllipseInRect(rectAtPoint(pos, 4))
            c.fillColor = v.gridColor
            c.drawRect(newRect(0, rowMaxY, v.bounds.width, 1))


    v.drawTimeRuler()
    v.drawCursor()
    
    let hasSelectionRect = v.selectionRect.width + v.selectionRect.height > 0.1
    if hasSelectionRect:
        c.strokeColor = newColor(0.0, 0.0, 0.5, 0.5)
        c.strokeWidth = 1.0
        c.fillColor = selectionColor
        c.drawRect(v.selectionRect)
        

proc dopesheetSelectionTrackingHandler(v: DopesheetView): proc(e: Event): bool =
    result = proc(e: Event): bool =
        result = true
        if v.editedAnimation.isNil: return
        if e.buttonState == bsDown:
            v.selectionRect = zeroRect
            v.selectionRect.origin = e.localPosition
            v.selectionOrigin = e.localPosition
            block findSelected:
                if v.selectedKeys.len > 0:
                    for sel in v.selectedKeys:
                        let rowMaxY = v.rowMaxY(sel.pi)
                        let k = v.editedAnimation.keyAtIndex(sel.pi, sel.ki)
                        if not k.isNil:
                            let pos = v.curvePointToLocal(newPoint(k.position, rowMaxY - v.rowHeight / 2))
                            if v.selectionRect.intersect(rectAtPoint(pos, 4)):
                                v.draggedKey = sel
                                break findSelected
                    
                    if not e.modifiers.anyCtrl():
                        v.clearSelection()

                for y, p in v.editedAnimation.properties:
                    let rowMaxY = v.rowMaxY(y)
                    for x, key in p.keys:
                        if key.position > v.toX: break
                        elif key.position >= v.fromX:
                            let pos = v.curvePointToLocal(newPoint(key.position, rowMaxY - v.rowHeight / 2))
                            if v.selectionRect.intersect(rectAtPoint(pos, 4)):
                                v.mSelectedKeys.incl((pi:y, ki:x))
                                v.draggedKey = v.selectedKeys[0]
                                break findSelected

            if not v.onKeysSelected.isNil:
                v.onKeysSelected(v.selectedKeys)

        elif e.buttonState == bsUnknown:
            let k = v.editedAnimation.keyAtIndex(v.draggedKey.pi, v.draggedKey.ki)
            if not k.isNil and not e.modifiers.anyCtrl():
                var p = v.localPointToCurve(e.localPosition)
                v.curveRoundToGrid(p.x)
                let diff = k.position - p.x                
                # echo "diff ", diff
                for sel in v.selectedKeys:
                    let k = v.editedAnimation.keyAtIndex(sel.pi, sel.ki)
                    if not k.isNil:
                        k.position -= diff
                        v.selectedKeysWasChanged = true
            else:
                let orig = v.selectionOrigin
                var topLeft = newPoint(0.0, 0.0)
                topLeft.x = min(orig.x, e.localPosition.x) 
                topLeft.y = min(orig.y, e.localPosition.y)

                var botRight = newPoint(0.0, 0.0)
                botRight.x = max(orig.x, e.localPosition.x)
                botRight.y = max(orig.y, e.localPosition.y)

                v.selectionRect.origin = topLeft
                v.selectionRect.size = newSize(botRight.x - topLeft.x, botRight.y - topLeft.y)
                #
                if not e.modifiers.anyCtrl():
                    v.clearSelection()
                for y, p in v.editedAnimation.properties:
                    let rowMaxY = v.rowMaxY(y)
                    for x, key in p.keys:
                        if key.position > v.toX: break
                        elif key.position >= v.fromX:
                            let pos = v.curvePointToLocal(newPoint(key.position, rowMaxY - v.rowHeight / 2))
                            if v.selectionRect.intersect(rectAtPoint(pos, 4)):
                                let s = (pi:y, ki:x)
                                # if s in v.mSelectedKeys:
                                #     v.mSelectedKeys.excl(s)
                                # else:
                                v.mSelectedKeys.incl(s)
                                # v.draggedKey = v.selectedKeys[0]
                v.draggedKey = (pi: -1, ki: -1)
        else: #bsUp
            # if v.draggedKey.pi == -1 and v.draggedKey.ki == -1:
            #     v.selectedKeys.clear()
            # else:
            v.draggedKey = (pi: -1, ki: -1)
            v.selectionRect = zeroRect
            if v.selectedKeysWasChanged and not v.onKeysChanged.isNil:
                v.onKeysChanged(v.selectedKeys)
            v.selectedKeysWasChanged = false

method onTouchEv*(v: DopesheetView, e: var Event): bool =
    if e.buttonState == bsDown:
        let pos = e.localPosition
        if pos.y < rulerHeight:
            v.mouseTrackingHandler = v.cursorTrackingHandler
        else:
            v.mouseTrackingHandler = v.dopesheetSelectionTrackingHandler

    result = procCall v.AnimationChartView.onTouchEv(e)

method onScroll*(v: DopesheetView, e: var Event): bool =
    if e.modifiers.anyShift():
        var dst = sgn(e.offset.y).Coord * 0.1
        if v.fromX + dst < 0.0:
            dst = -v.fromX
        elif v.toX + dst > 1.0:
            dst = 1.0 - v.toX
        v.fromX += dst
        v.toX += dst
    else:
        let allowZoom = e.offset.y > 0 or v.localGridSize().width * 3 < v.bounds.width
        v.processZoomEvent(e, allowZoom, false)
        v.toX = clamp(v.toX, 0.0, 1.0)

    result = true

method acceptsFirstResponder*(v: DopesheetView): bool = true

registerClass(DopesheetView)
