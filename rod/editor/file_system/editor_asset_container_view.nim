import nimx / [ view, collection_view, types, context, view_event_handling,
                drag_and_drop, text_field, pasteboard/pasteboard_item,
                view_render_to_image ]

import os

import editor_asset_icon_view

export collection_view

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
    onItemRenamed*: proc(item:int)
    mIsCompact: bool

proc newAssetContainerView*(r: Rect): AssetContainerView=
    result = new(AssetContainerView)
    result.backgroundColor = whiteColor()
    result.layoutDirection = LayoutDirection.TopDown
    result.itemSize = newSize(128.0, 128.0)
    result.layoutWidth = 0
    result.offset = 35.0
    result.init(r)
    result.selectedItems = @[]
    result.removeAllGestureDetectors()

proc reload*(v: AssetContainerView)=
    v.selectedItems.setLen(0)
    v.updateLayout()

proc setCompact*(v: AssetContainerView, val: bool)=
    if v.mIsCompact != val:
        v.mIsCompact = val
        if not val:
            v.itemSize = newSize(128.0, 128.0)
        else:
            v.itemSize = newSize(256.0, 32.0)
        v.reload()

template isCompact*(v: AssetContainerView): bool = v.mIsCompact

proc selectItem(v: AssetContainerView, i: int, notify: bool = true)=
    # if i >= 0 and i < v.subviews.len:
    let subv = v.subviews[i]
    subv.backgroundColor = selectionColor
    if notify and not v.onItemSelected.isNil:
        # echo "select ", i
        v.onItemSelected(i)

proc deselectItem(v: AssetContainerView, i: int, notify: bool = true)=
    # if i >= 0 and i < v.subviews.len:
    let subv = v.subviews[i]
    subv.backgroundColor = clearColor()
    if notify and not v.onItemDeselected.isNil:
        # echo "deselect ", i
        v.onItemDeselected(i)

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
                    # v.selectedItems.setLen(0)
                    if dragLen > 10.0:
                        # sub.backgroundColor = selectionColor
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

        for i, subv in v.subviews:
            if subv.frame.intersect(v.selectionRect):
                v.selectItem(i, false)
            else:
                v.deselectItem(i, false)

    else:
        if v.dragStarted:
            # echo "draging"
            # v.selectedItems.setLen(0)
            v.selectionRect = zeroRect
        else:
            let hasSelectionRect = v.selectionRect.width + v.selectionRect.height > 5.0
            var selected = newSeq[int]()

            if hasSelectionRect:
                # echo "hasSelectionRect"
                for i, subv in v.subviews:
                    if subv.frame.intersect(v.selectionRect):
                        v.selectItem(i, false)
                        selected.add(i)
                    elif i in v.selectedItems:
                        v.deselectItem(i)
            else:
                if v.selectedItems.len > 1:
                    # echo "selitems > 1"
                    for si in v.selectedItems:
                        if v.subviews[si].frame.contains(v.selectionOrigin):
                            v.selectItem(si)
                            selected.add(si)
                        else:
                            v.deselectItem(si)

                    v.selectedItems.setLen(0)
                else:
                    var dc = newSeq[int]()

                    for i, subv in v.subviews:
                        # echo "subv nil ", subv.isNil, " ", v.isNil
                        if subv.frame.contains(v.selectionOrigin):
                            if i in v.selectedItems and not v.onItemDoubleClick.isNil:
                                dc.add(i)
                                # v.deselectItem(i)
                                # v.onItemDoubleClick(i)
                                v.selectedItems.setLen(0)
                            else:
                                v.selectItem(i)
                                selected.add(i)

                        elif i in v.selectedItems:
                            v.deselectItem(i)

                    for i in dc:
                        v.deselectItem(i)
                        v.onItemDoubleClick(i)

            v.selectedItems = selected
            v.selectionRect = zeroRect

    result = true
    discard v.makeFirstResponder()

method onKeyDown*(v: AssetContainerView, e: var Event):bool=
    if not v.isFirstResponder: return
    case e.keyCode:
    of VirtualKey.Delete:
        if v.subviews.len == 0: return
        if not v.onItemsDelete.isNil and v.selectedItems.len > 0:
            v.onItemsDelete(v.selectedItems)
            v.selectedItems.setLen(0)

        result = true

    of VirtualKey.Up, VirtualKey.Down, VirtualKey.Left, VirtualKey.Right:
        if v.subviews.len == 0: return
        if v.selectedItems.len == 0:
            v.selectedItems.add(0)
            v.selectItem(0)
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
                    v.deselectItem(sel)

                v.selectedItems.setLen(0)
            else:
                last = v.selectedItems[^1]

            step = clamp(step + last, 0, v.subviews.len - 1)
            v.selectedItems.add(step)

            for sel in v.selectedItems:
                last = sel
                v.selectItem(sel)

        result = true

    of VirtualKey.Space:
        if v.subviews.len == 0: return
        if v.selectedItems.len == 1 and not v.onItemDoubleClick.isNil:
            v.onItemDoubleClick(v.selectedItems[0])
            result = true

    of VirtualKey.Backspace:
        if not v.onBackspace.isNil():
            v.onBackspace()
            result = true

    of VirtualKey.Return:
        if v.subviews.len == 0: return
        if v.selectedItems.len == 1 and not v.onItemRenamed.isNil:
            v.onItemRenamed(v.selectedItems[0])
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

