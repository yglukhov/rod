import nimx.view
import nimx.collection_view
import nimx.types
import nimx.event
import nimx.context
import nimx.view_event_handling_new
import nimx.drag_and_drop
import nimx.pasteboard.pasteboard_item
import nimx.view_render_to_image
import os

const selectionColor = newColor(0.0, 0.0, 0.5, 0.2)

type AssetContainerView* = ref object of CollectionView
    selectedIndex: int
    selectionRect: Rect
    selectionOrigin: Point
    dragStarted: bool
    selectedItems*: seq[int]
    onItemDeselected*: proc(item: int)
    onItemSelected*: proc(item: int)
    onItemDoubleClick*: proc(item: int)
    onItemsDelete*: proc(item:seq[int])
    onBackspace*: proc()
    onItemsDragStart*: proc(item: seq[int])

proc newAssetContainerView*(r: Rect): AssetContainerView=
    result = new(AssetContainerView)
    result.backgroundColor = whiteColor()
    result.layoutDirection = LayoutDirection.TopDown
    result.itemSize = newSize(100.0, 100.0)
    result.layoutWidth = 0
    result.offset = 35.0
    result.init(r)
    result.selectedItems = @[]
    result.removeAllGestureDetectors()

proc reload*(v: AssetContainerView)=
    v.selectedItems.setLen(0)
    v.updateLayout()

method onTouchEv*(v: AssetContainerView, e: var Event): bool =
    discard procCall v.View.onTouchEv(e)

    if e.buttonState == bsDown:
        v.dragStarted = false
        v.selectionRect = zeroRect
        v.selectionOrigin = e.localPosition

    elif e.buttonState == bsUnknown:
        if v.dragStarted: return false

        var orig = v.selectionOrigin
        var dragLen = v.selectionOrigin.distanceTo(e.localPosition)
        if not v.onItemsDragStart.isNil:
            for i, sub in v.subviews:
                if sub.frame.contains(orig):
                    v.selectedItems.setLen(0)
                    if dragLen > 10.0:
                        sub.backgroundColor = selectionColor
                        v.onItemsDragStart(@[i])
                        v.dragStarted = true
                        return false
                    return true

        var topLeft = newPoint(0.0, 0.0)
        topLeft.x = min(orig.x, e.localPosition.x)
        topLeft.y = min(orig.y, e.localPosition.y)

        var botRight = newPoint(0.0, 0.0)
        botRight.x = max(orig.x, e.localPosition.x)
        botRight.y = max(orig.y, e.localPosition.y)

        v.selectionRect.origin = topLeft
        v.selectionRect.size = newSize(botRight.x - topLeft.x, botRight.y - topLeft.y)

        for subv in v.subviews:
            if subv.frame.intersect(v.selectionRect):
                subv.backgroundColor = selectionColor
            else:
                subv.backgroundColor = clearColor()

    else:
        if v.dragStarted:
            v.selectedItems.setLen(0)
            v.selectionRect = zeroRect

        let hasSelectionRect = v.selectionRect.width + v.selectionRect.height > 0.1
        var selected = newSeq[int]()
        var doubleClick = false

        if v.selectedItems.len > 1:
            v.selectedItems.setLen(0)

        for i, subv in v.subviews:
            if subv.isNil: continue
            if hasSelectionRect and subv.frame.intersect(v.selectionRect):
                subv.backgroundColor = selectionColor
                selected.add(i)

            elif subv.frame.contains(v.selectionOrigin):
                if i in v.selectedItems and not v.onItemDoubleClick.isNil:
                    if not v.onItemDeselected.isNil:
                        v.onItemDeselected(i)

                    v.onItemDoubleClick(i)
                    doubleClick = true
                    v.selectedItems.setLen(0)
                    subv.backgroundColor = clearColor()
                else:
                    subv.backgroundColor = selectionColor
                    selected.add(i)
            else:
                subv.backgroundColor = clearColor()

        if not v.onItemSelected.isNil and not doubleClick:
            for i, subv in v.subviews:
                if i in selected:
                    v.onItemSelected(i)
                elif not v.onItemDeselected.isNil:
                    v.onItemDeselected(i)

        v.selectedItems = selected

        v.selectionRect = newRect(0.0, 0.0, 0.0, 0.0)

    result = true
    discard v.makeFirstResponder()

method onKeyDown*(v: AssetContainerView, e: var Event):bool=
    case e.keyCode:
    of VirtualKey.Delete:
        if not v.onItemsDelete.isNil and v.selectedItems.len > 0:
            v.onItemsDelete(v.selectedItems)
            v.selectedItems.setLen(0)

        result = true

    of VirtualKey.Up, VirtualKey.Down, VirtualKey.Left, VirtualKey.Right:
        if v.selectedItems.len == 0:
            v.selectedItems.add(0)
            v.subviews[0].backgroundColor = selectionColor
        else:
            let itemsInLine = v.columnCount
            var step = if e.keyCode == VirtualKey.Left: -1
                       elif e.keyCode == VirtualKey.Right: 1
                       elif e.keyCode == VirtualKey.Up: -itemsInLine
                       else: itemsInLine


            var last = -1
            if not e.modifiers.anyCtrl():
                for sel in v.selectedItems:
                    last = sel
                    v.subviews[sel].backgroundColor = clearColor()

                v.selectedItems.setLen(0)
            else:
                last = v.selectedItems[^1]

            step = clamp(step + last, 0, v.subviews.len - 1)
            v.selectedItems.add(step)

            for sel in v.selectedItems:
                last = sel
                v.subviews[sel].backgroundColor = selectionColor

        result = true

    of VirtualKey.Space:
        if v.selectedItems.len == 1 and not v.onItemDoubleClick.isNil:
            v.onItemDoubleClick(v.selectedItems[0])
            result = true

    of VirtualKey.Backspace:
        if not v.onBackspace.isNil():
            v.onBackspace()
            result = true

    else: discard

method draw*(v: AssetContainerView, r: Rect)=
    procCall v.CollectionView.draw(r)
    let hasSelectionRect = v.selectionRect.width + v.selectionRect.height > 0.1
    if hasSelectionRect:
        let c = currentContext()
        c.strokeColor = newColor(0.0, 0.0, 0.5, 0.5)
        c.strokeWidth = 1.0
        c.fillColor = selectionColor
        c.drawRect(v.selectionRect)

