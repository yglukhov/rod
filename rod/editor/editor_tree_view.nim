import nimx / [outline_view, types, matrixes, view, table_view_cell, text_field,
    scroll_view, button, event, formatted_text, font]

import rod.edit_view
import variant, strutils, tables
import rod / [node, rod_types]

type EditorTreeView* = ref object of EditorTabView
    outlineView: OutlineView
    filterField: TextField
    renameField: TextField

proc onTreeChanged(v: EditorTreeView)=
    v.filterField.sendAction()
    v.editor.sceneTreeDidChange()

proc getTreeViewIndexPathForNode(v: EditorTreeView, n: Node, indexPath: var seq[int])

proc nodeFromSelectedOutlinePath(v: EditorTreeView): Node=
    var sip = v.outlineView.selectedIndexPath
    result = v.rootNode
    if sip.len == 0:
        sip.add(0)
    else:
        result = v.outlineView.itemAtIndexPath(sip).get(Node)


method init*(v: EditorTreeView, r: Rect)=
    procCall v.View.init(r)

    v.filterField = newTextField(newRect(0.0, 0.0, r.width, 20.0))
    v.filterField.autoresizingMask = {afFlexibleWidth}
    v.filterField.continuous = true
    v.filterField.onAction do():
        v.outlineView.reloadData()

    v.addSubview(v.filterField)

    v.renameField = newTextField(newRect(0.0, 0.0, r.width, 30.0))
    v.renameField.autoresizingMask = {afFlexibleWidth}


    let outlineView = OutlineView.new(newRect(0.0, 25.0, r.width, r.height - 20))
    v.outlineView = outlineView

    outlineView.autoresizingMask = { afFlexibleWidth, afFlexibleMaxX }
    outlineView.numberOfChildrenInItem = proc(item: Variant, indexPath: openarray[int]): int =
        if indexPath.len == 0:
            result = 1
        else:
            let n = item.get(Node)
            result = n.children.len

    outlineView.childOfItem = proc(item: Variant, indexPath: openarray[int]): Variant =
        if indexPath.len == 1:
            return newVariant(v.rootNode)
        else:
            return newVariant(item.get(Node).children[indexPath[^1]])

    outlineView.createCell = proc(): TableViewCell =
        var lbl = newLabel(newRect(0, 0, 100, 20))
        result = newTableViewCell(lbl)
        result.autoresizingMask = {afFlexibleWidth}
        # var btn = newCheckbox(newRect(80.0, 0.0, 20.0, 20.0))
        # btn.autoResizingMask = {afFlexibleMinX}
        # result.addSubview(btn)

    outlineView.setDisplayFilter do(item: Variant)-> bool:
        if v.filterField.text.len == 0:
            return true

        var n: Node
        try:
            n = item.get(Node)
        except:
            return false

        let filter = v.filterField.text.toLowerAscii()
        let lowName = n.name.toLowerAscii()
        if filter == lowName or filter in lowName:
            return true

    outlineView.configureCell = proc (cell: TableViewCell, indexPath: openarray[int]) =
        let n = outlineView.itemAtIndexPath(indexPath).get(Node)
        # echo "configure ", @indexPath, " node ", n.name
        let textField = TextField(cell.subviews[0])

        # var btn = Button(cell.subviews[1])
        # btn.value = n.enabled.int8
        if not n.isEnabledInTree():
            textField.textColor = newColor(0.3, 0.3, 0.3, 1.0)
        else:
            textField.textColor = newGrayColor(0.0)

        textField.text = if n.name.len == 0: "(node)" else: n.name

        # btn.onAction do():
        #     n.enabled = not n.enabled
        #     v.onTreeChanged()

        if v.filterField.text.len() > 0:
            let lowerFilter= v.filterField.text.toLowerAscii()
            let lowerField = textField.text.toLowerAscii()
            let start = lowerField.find(lowerFilter)
            if start > -1:
                textField.formattedText.setTextColorInRange(start, start + lowerFilter.len, newColor(0.9, 0.9, 0.9, 1.0))

    outlineView.onSelectionChanged = proc() =
        if not v.renameField.superview.isNil:
            v.renameField.removeFromSuperview()

        let ip = outlineView.selectedIndexPath
        if ip.len == 0:
            return

        let n = if ip.len > 0:
                outlineView.itemAtIndexPath(ip).get(Node)
            else:
                nil

        v.editor.selectedNode = n

    outlineView.onDragAndDrop = proc(fromIp, toIp: openarray[int]) =
        let f = outlineView.itemAtIndexPath(fromIp).get(Node)
        var tos = @toIp
        tos.setLen(tos.len - 1)
        let t = outlineView.itemAtIndexPath(tos).get(Node)
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

        v.onTreeChanged()

    outlineView.reloadData()

    let outlineScrollView = newScrollView(outlineView)
    outlineScrollView.resizingMask = "wh"
    outlineScrollView.onScroll do():
        if not v.renameField.superview.isNil:
            v.renameField.removeFromSuperview()
            discard v.outlineView.makeFirstResponder()

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
            n = outlineView.itemAtIndexPath(sip).get(Node)

        outlineView.expandRow(sip)
        discard n.newChild("New Node")
        sip.add(n.children.len - 1)

        v.onTreeChanged()

        outlineView.selectItemAtIndexPath(sip)
    v.addSubview(createNodeButton)

    let deleteNodeButton = Button.new(newRect(24, v.bounds.height - 20, 20, 20))
    deleteNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    deleteNodeButton.title = "-"
    deleteNodeButton.onAction do():
        if outlineView.selectedIndexPath.len != 0:
            let n = outlineView.itemAtIndexPath(outlineView.selectedIndexPath).get(Node)
            n.removeFromParent()
            var sip = outlineView.selectedIndexPath
            sip.delete(sip.len-1)
            outlineView.selectItemAtIndexPath(sip)

            v.onTreeChanged()

    v.addSubview(deleteNodeButton)

method onKeyDown*(v: EditorTreeView, e: var Event): bool =
    if e.keyCode == VirtualKey.Return:
        let n = v.nodeFromSelectedOutlinePath()

        if v.renameField.superview.isNil:
            if v.outlineView.selectedIndexPath.len > 0 and v.outlineView.isFirstResponder():
                var cell = v.outlineView.cellAtIndexPath(v.outlineView.selectedIndexPath)
                v.renameField.text = n.name
                v.renameField.setFrame(newRect(newPoint(15.0, cell.frame.y), cell.frame.size))
                v.outlineView.superview.addSubview(v.renameField)
                discard v.window.makeFirstResponder(v.renameField)
            else:
                discard v.window.makeFirstResponder(v.outlineView)
        else:
            if not v.renameField.superview.isNil and v.renameField.isFirstResponder():
                n.name = v.renameField.text
                v.renameField.removeFromSuperview()

            discard v.window.makeFirstResponder(v.outlineView)

        result = true

    elif e.keyCode == VirtualKey.Escape:
        v.filterField.text = ""
        v.filterField.sendAction()
        if not v.renameField.superview.isNil:
            v.renameField.removeFromSuperview()

        discard v.outlineView.makeFirstResponder()
        result = true

    elif e.keyCode == VirtualKey.F and e.modifiers.anyOsModifier():
        discard v.filterField.makeFirstResponder()
        result = true

    elif e.keyCode == VirtualKey.H and e.modifiers.anyOsModifier():
        let n = v.nodeFromSelectedOutlinePath()
        n.enabled = not n.enabled
        v.onTreeChanged()
        result = true

    elif e.keyCode == VirtualKey.N and e.modifiers.anyOsModifier():
        let n = v.nodeFromSelectedOutlinePath()
        var sip = v.outlineView.selectedIndexPath
        if sip.len == 0:
            sip.add(0)
        v.outlineView.expandRow(sip)
        discard n.newChild("New Node")
        if not e.modifiers.anyShift():
            sip.add(n.children.len - 1)
            v.onTreeChanged()
            v.outlineView.selectItemAtIndexPath(sip)

    elif e.keyCode == VirtualKey.Delete:
        if v.renameField.isFirstResponder() or v.filterField.isFirstResponder(): return false
        var sip = v.outlineView.selectedIndexPath
        if sip.len == 0:
            return
        if sip[^1] > 0:
            sip[^1].dec
        elif sip.len > 1:
            sip = sip[0..^2]

        let n = v.nodeFromSelectedOutlinePath()

        n.removeFromParent()
        v.outlineView.selectItemAtIndexPath(sip)
        v.onTreeChanged()
        v.editor.selectedNode = nil

        result = true

proc getTreeViewIndexPathForNode(v: EditorTreeView, n: Node, indexPath: var seq[int]) =
    # running up and calculate the path to the node in the tree
    if v.rootNode == n:
        indexPath.add(0)
        # indexPath.add(1)
    else:
        let rootParent = v.rootNode

        var p = n.parent
        var n = n
        while not p.isNil and n != rootParent:
            indexPath.insert(p.children.find(n), 0)
            n = p
            p = p.parent

        indexPath.insert(0,0)

method setEditedNode*(v: EditorTreeView, n: Node)=
    var indexPath = newSeq[int]()
    if not n.isNil:
        v.getTreeViewIndexPathForNode(n, indexPath)

        v.outlineView.expandBranch(indexPath[0..^2])

        if indexPath.len > 0: # todo: check this!
            v.outlineView.selectItemAtIndexPath(indexPath)
    else:
        v.outlineView.selectItemAtIndexPath(indexPath)

method onEditorTouchDown*(v: EditorTreeView, e: var Event)=
    v.outlineView.reloadData()

method onSceneChanged*(v: EditorTreeView)=
    v.outlineView.reloadData()

method tabSize*(v: EditorTreeView, bounds: Rect): Size=
    result = newSize(200.0, bounds.height)

method tabAnchor*(v: EditorTreeView): EditorTabAnchor =
    result = etaLeft

var frames = 0
const framesPerUpdate = 15

method update*(v: EditorTreeView)=
    inc frames
    if frames > framesPerUpdate:
        v.outlineView.reloadData()
        frames = 0

method onCompositionChanged*(v: EditorTreeView, comp: CompositionDocument) =
    v.rootNode = comp.rootNode
    v.outlineView.reloadData()
    v.setEditedNode(comp.selectedNode)

registerEditorTab("Tree", EditorTreeView)
