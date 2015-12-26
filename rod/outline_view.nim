import nimx.view
import nimx.context
import nimx.composition
import nimx.font
import nimx.types
import nimx.event
import nimx.table_view_cell
import nimx.view_event_handling

import typetraits
import math
import variant

# Quick and dirty implementation of outline view

type ItemNode = ref object
    expanded: bool
    expandable: bool
    children: seq[ItemNode]
    item: Variant
    cell: TableViewCell

type OutlineView* = ref object of View
    rootItem: ItemNode
    selectedIndexPath*: seq[int]
    numberOfChildrenInItem*: proc(item: Variant, indexPath: openarray[int]): int
    childOfItem*: proc(item: Variant, indexPath: openarray[int]): Variant
    createCell*: proc(): TableViewCell
    configureCell*: proc (cell: TableViewCell, indexPath: openarray[int])
    onSelectionChanged*: proc()
    tempIndexPath: seq[int]

method init*(v: OutlineView, r: Rect) =
    procCall v.View.init(r)
    v.rootItem = ItemNode.new()
    v.tempIndexPath = newSeq[int]()
    v.selectedIndexPath = newSeq[int]()

const rowHeight = 20.Coord

var disclosureTriangleComposition = newComposition """
uniform float uAngle;
void compose() {
    vec2 center = vec2(bounds.x + bounds.z / 2.0, bounds.y + bounds.w / 2.0 - 1.0);
    float triangle = sdRegularPolygon(center, 4.0, 3, uAngle);
    drawShape(triangle, vec4(0.0, 0, 0, 1));
}
"""

proc drawDisclosureTriangle(disclosed: bool, r: Rect) =
    disclosureTriangleComposition.draw r:
        setUniform("uAngle", if disclosed: Coord(PI / 2.0) else: Coord(0))
    discard

proc drawNode(v: OutlineView, n: ItemNode, y: var Coord) =
    let c = currentContext()
    if n.cell.isNil:
        n.cell = v.createCell()
    n.cell.selected = v.tempIndexPath == v.selectedIndexPath
    let indent = Coord(3 + v.tempIndexPath.len * 3)
    n.cell.setFrame(newRect(indent, y, v.bounds.width - indent, rowHeight))
    v.configureCell(n.cell, v.tempIndexPath)
    n.cell.drawWithinSuperview()
    if n.expandable:
        drawDisclosureTriangle(n.expanded, newRect(indent - 6, y, 6, rowHeight))

    y += rowHeight
    if n.expanded and not n.children.isNil:
        let lastIndex = v.tempIndexPath.len
        v.tempIndexPath.add(0)
        for i, c in n.children:
            v.tempIndexPath[lastIndex] = i
            v.drawNode(c, y)
        v.tempIndexPath.setLen(lastIndex)

method draw*(v: OutlineView, r: Rect) =
    var y = 0.Coord
    if not v.rootItem.children.isNil:
        v.tempIndexPath.setLen(1)
        for i, c in v.rootItem.children:
            v.tempIndexPath[0] = i
            v.drawNode(c, y)

proc nodeAtIndexPath(v: OutlineView, indexPath: openarray[int]): ItemNode =
    result = v.rootItem
    for i in indexPath:
        result = result.children[i]

proc setRowExpanded*(v: OutlineView, expanded: bool, indexPath: openarray[int]) =
    v.nodeAtIndexPath(indexPath).expanded = expanded

proc expandRow*(v: OutlineView, indexPath: openarray[int]) =
    v.setRowExpanded(true, indexPath)

proc collapseRow*(v: OutlineView, indexPath: openarray[int]) =
    v.setRowExpanded(false, indexPath)

proc itemAtIndexPath*(v: OutlineView, indexPath: openarray[int]): Variant =
    v.nodeAtIndexPath(indexPath).item

proc itemAtPos(v: OutlineView, n: ItemNode, p: Point, y: var Coord): ItemNode =
    y += rowHeight
    if p.y < y: return n
    if n.expanded and not n.children.isNil:
        let lastIndex = v.tempIndexPath.len
        v.tempIndexPath.add(0)
        for i, c in n.children:
            v.tempIndexPath[lastIndex] = i
            result = v.itemAtPos(c, p, y)
            if not result.isNil: return
        v.tempIndexPath.setLen(lastIndex)

proc itemAtPos(v: OutlineView, p: Point): ItemNode =
    v.tempIndexPath.setLen(1)
    var y = 0.Coord
    if not v.rootItem.children.isNil:
        for i, c in v.rootItem.children:
            v.tempIndexPath[0] = i
            result = v.itemAtPos(c, p, y)
            if not result.isNil: break

proc reloadDataForNode(v: OutlineView, n: ItemNode) =
    let childrenCount = v.numberOfChildrenInItem(n.item, v.tempIndexPath)
    if childrenCount > 0 and n.children.isNil:
        n.children = newSeq[ItemNode](childrenCount)
    elif not n.children.isNil:
        n.children.setLen(childrenCount)
    let lastIndex = v.tempIndexPath.len
    v.tempIndexPath.add(0)
    for i in 0 ..< childrenCount:
        v.tempIndexPath[lastIndex] = i
        if n.children[i].isNil:
            n.children[i] = ItemNode(expandable: true)
        if not v.childOfItem.isNil:
            n.children[i].item = v.childOfItem(n.item, v.tempIndexPath)
        v.reloadDataForNode(n.children[i])
    v.tempIndexPath.setLen(lastIndex)

proc reloadData*(v: OutlineView) =
    v.tempIndexPath.setLen(0)
    v.reloadDataForNode(v.rootItem)

template selectionChanged(v: OutlineView) =
    if not v.onSelectionChanged.isNil: v.onSelectionChanged()

method onMouseDown*(v: OutlineView, e: var Event): bool =
    result = true
    let pos = e.localPosition
    let i = v.itemAtPos(pos)
    if not i.isNil:
        if pos.x < 10 and i.expandable:
            i.expanded = not i.expanded
        elif v.tempIndexPath == v.selectedIndexPath:
            v.selectedIndexPath.setLen(0)
            v.selectionChanged()
        else:
            v.selectedIndexPath = v.tempIndexPath
            v.selectionChanged()
        v.setNeedsDisplay()
