import nimx.view
import nimx.types
import nimx.button

import node
import panel_view
import outline_view
import inspector_view
import rod_types

import nimx.text_field
import nimx.table_view_cell

import variant

type Editor* = ref object
    rootNode*: Node3D
    eventCatchingView*: View
    treeView*: View

proc newTreeView(e: Editor, inspector: InspectorView): PanelView =
    result = PanelView.new(newRect(0, 0, 200, 500))
    let title = newLabel(newRect(2, 2, 100, 15))
    title.text = "Tree view"
    result.addSubview(title)

    let outlineView = OutlineView.new(newRect(0, 20, result.bounds.width, result.bounds.height - 40))
    outlineView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
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
            return newVariant(e.rootNode)
        else:
            return newVariant(item.get(Node3D).children[indexPath[^1]])

    outlineView.createCell = proc(): TableViewCell =
        result = newTableViewCell(newLabel(newRect(0, 0, 100, 20)))

    outlineView.configureCell = proc (cell: TableViewCell, indexPath: openarray[int]) =
        let n = outlineView.itemAtIndexPath(indexPath).get(Node3D)
        let textField = TextField(cell.subviews[0])
        textField.text = if n.name.isNil: "(nil)" else: n.name

    outlineView.onSelectionChanged = proc() =
        let ip = outlineView.selectedIndexPath
        let n = if ip.len > 0:
                outlineView.itemAtIndexPath(ip).get(Node3D)
            else:
                nil
        inspector.inspectedNode = n

    outlineView.reloadData()
    result.addSubview(outlineView)

    let createNodeButton = Button.new(newRect(2, result.bounds.height - 20, 20, 20))
    createNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    createNodeButton.title = "+"
    createNodeButton.onAction do():
        let n = outlineView.itemAtIndexPath(outlineView.selectedIndexPath).get(Node3D)
        discard n.newChild("New Node")
        outlineView.reloadData()
    result.addSubview(createNodeButton)

    let deleteNodeButton = Button.new(newRect(24, result.bounds.height - 20, 20, 20))
    deleteNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    deleteNodeButton.title = "-"
    deleteNodeButton.onAction do():
        let n = outlineView.itemAtIndexPath(outlineView.selectedIndexPath).get(Node3D)
        n.removeFromParent()
        outlineView.reloadData()
    result.addSubview(deleteNodeButton)

proc startEditingNodeInView*(n: Node3D, v: View): Editor =
    result.new()
    result.rootNode = n

    let inspectorView = InspectorView.new(newRect(200, 0, 200, 500))
    result.treeView = newTreeView(result, inspectorView)
    v.window.addSubview(result.treeView)
    v.window.addSubview(inspectorView)

proc endEditing*(e: Editor) =
    discard
