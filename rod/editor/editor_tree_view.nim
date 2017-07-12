import nimx / [outline_view, types, matrixes, view, table_view_cell, text_field,
    scroll_view, button, event]

import editor_tab
import variant
import rod / [node, rod_types]

type EditorTreeView* = ref object of EditorTabView
    outlineView: OutlineView
    onNodeSelected*: proc(n: Node)
    mOnTreeChanged: proc()

proc onTreeChanged*(v: EditorTreeView, cb: proc)=
    v.mOnTreeChanged = proc()=
        v.outlineView.reloadData()
        cb()

method init*(v: EditorTreeView, r: Rect)=
    procCall v.View.init(r)

    let outlineView = OutlineView.new(newRect(0, 0, r.width, r.height - 20))
    v.outlineView = outlineView

    outlineView.autoresizingMask = { afFlexibleWidth, afFlexibleMaxX }
    outlineView.numberOfChildrenInItem = proc(item: Variant, indexPath: openarray[int]): int =
        if indexPath.len == 0:
            return 1
        else:
            let n = item.get(Node3D)
            if n.children.isNil:
                return 0
            else:
                return n.children.len

    outlineView.childOfItem = proc(item: Variant, indexPath: openarray[int]): Variant =
        if indexPath.len == 1:
            return newVariant(v.rootNode)
        else:
            return newVariant(item.get(Node3D).children[indexPath[^1]])

    outlineView.createCell = proc(): TableViewCell =
        result = newTableViewCell(newLabel(newRect(0, 0, 100, 20)))

    outlineView.configureCell = proc (cell: TableViewCell, indexPath: openarray[int]) =
        let n = outlineView.itemAtIndexPath(indexPath).get(Node3D)
        let textField = TextField(cell.subviews[0])
        if not cell.selected:
            textField.textColor = newGrayColor(0.9)
        else:
            textField.textColor = newGrayColor(0.0)
        textField.text = if n.name.isNil: "(nil)" else: n.name

    outlineView.onSelectionChanged = proc() =
        let ip = outlineView.selectedIndexPath
        let n = if ip.len > 0:
                outlineView.itemAtIndexPath(ip).get(Node3D)
            else:
                v.rootNode

        if not v.onNodeSelected.isNil():
            v.onNodeSelected(n)

    outlineView.onDragAndDrop = proc(fromIp, toIp: openarray[int]) =
        let f = outlineView.itemAtIndexPath(fromIp).get(Node3D)
        var tos = @toIp
        tos.setLen(tos.len - 1)
        let t = outlineView.itemAtIndexPath(tos).get(Node3D)
        let toIndex = toIp[^1]
        if f.parent == t:
            let cIndex = t.children.find(f)
            if toIndex < cIndex:
                t.children.delete(cIndex)
                t.children.insert(f, toIndex)
            elif toIndex > cIndex:
                t.children.delete(cIndex)
                t.children.insert(f, toIndex - 1)
        else:
            f.removeFromParent()
            t.insertChild(f, toIndex)

        if not v.mOnTreeChanged.isNil():
            v.mOnTreeChanged()

    outlineView.reloadData()

    let outlineScrollView = newScrollView(outlineView)
    outlineScrollView.resizingMask = "wh"
    v.addSubview(outlineScrollView)

    let createNodeButton = Button.new(newRect(2, v.bounds.height - 20, 20, 20))
    createNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    createNodeButton.title = "+"
    createNodeButton.onAction do():
        var sip = outlineView.selectedIndexPath
        var n = v.rootNode
        if sip.len == 0:
            sip.add(0)
        else:
            n = outlineView.itemAtIndexPath(sip).get(Node3D)

        outlineView.expandRow(sip)
        discard n.newChild("New Node")
        sip.add(n.children.len - 1)
        if not v.mOnTreeChanged.isNil():
            v.mOnTreeChanged()

        outlineView.selectItemAtIndexPath(sip)
    v.addSubview(createNodeButton)

    let deleteNodeButton = Button.new(newRect(24, v.bounds.height - 20, 20, 20))
    deleteNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    deleteNodeButton.title = "-"
    deleteNodeButton.onAction do():
        if outlineView.selectedIndexPath.len != 0:
            let n = outlineView.itemAtIndexPath(outlineView.selectedIndexPath).get(Node3D)
            n.removeFromParent()
            var sip = outlineView.selectedIndexPath
            sip.delete(sip.len-1)
            outlineView.selectItemAtIndexPath(sip)
            if not v.mOnTreeChanged.isNil():
                v.mOnTreeChanged()

    v.addSubview(deleteNodeButton)

    let refreshButton = Button.new(newRect(46, v.bounds.height - 20, 60, 20))
    refreshButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    refreshButton.title = "Refresh"
    refreshButton.onAction do():
        if not v.mOnTreeChanged.isNil():
            v.mOnTreeChanged()

    v.addSubview(refreshButton)


proc getTreeViewIndexPathForNode(v: EditorTreeView, n: Node3D, indexPath: var seq[int]) =
    # running up and calculate the path to the node in the tree
    let parent = n.parent
    if not parent.isNil:
        indexPath.insert(parent.children.find(n), 0)

    # because there is the root node, it's necessary to add 0
    elif parent.isNil or parent == v.rootNode:
        indexPath.insert(0, 0)
        return

    v.getTreeViewIndexPathForNode(parent, indexPath)

method editedNode*(v: EditorTreeView, n: Node)=
    if not n.isNil:
        var indexPath = newSeq[int]()
        v.getTreeViewIndexPathForNode(n, indexPath)
        if indexPath.len > 0:
            v.outlineView.expandRow(indexPath)

method selectedNode*(v: EditorTreeView, n: Node)=
    var indexPath = newSeq[int]()
    v.getTreeViewIndexPathForNode(n, indexPath)
    if indexPath.len > 0:
        if not v.onNodeSelected.isNil():
            v.onNodeSelected(n)

method onEditorTouchDown*(v: EditorTreeView, e: var Event)=
    v.outlineView.reloadData()

method onSceneChanged*(v: EditorTreeView)=
    v.outlineView.reloadData()

method tabSize*(v: EditorTreeView, bounds: Rect): Size=
    result = newSize(200.0, bounds.height)

method tabAnchor*(v: EditorTreeView): EditorTabAnchor =
    result = etaLeft

registerEditorTad("Tree", EditorTreeView)