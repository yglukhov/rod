import nimx.view
import nimx.types
import nimx.button

import node
import panel_view
import outline_view
import inspector_view
import rod_types

import nimx.animation
import nimx.text_field
import nimx.table_view_cell

import rod.scene_composition
import rod.component.mesh_component

import variant

when defined(js):
    import dom
elif not defined(android) and not defined(ios):
    import native_dialogs

type Editor* = ref object
    rootNode*: Node3D
    eventCatchingView*: View
    treeView*: View
    selectedNode*: Node3D

proc newTreeView(e: Editor, inspector: InspectorView): PanelView =
    result = PanelView.new(newRect(0, 0, 200, 700))
    result.collapsible = true

    let title = newLabel(newRect(22, 6, 108, 15))
    title.textColor = newGrayColor(1.0)
    title.text = "Scene"

    result.addSubview(title)

    let outlineView = OutlineView.new(newRect(1, 28, result.bounds.width - 3, result.bounds.height - 40))
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
                nil


        if not e.selectedNode.isNil:
            let mesh = e.selectedNode.componentIfAvailable(MeshComponent)
            if not mesh.isNil:
                mesh.bShowObjectSelection = false

        inspector.inspectedNode = n

        e.selectedNode = n

        if not e.selectedNode.isNil:
            let mesh = e.selectedNode.componentIfAvailable(MeshComponent)
            if not mesh.isNil:
                mesh.bShowObjectSelection = true

    outlineView.reloadData()
    result.addSubview(outlineView)

    let createNodeButton = Button.new(newRect(2, result.bounds.height - 20, 20, 20))
    # createNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    createNodeButton.title = "+"
    createNodeButton.onAction do():
        var sip = outlineView.selectedIndexPath
        var n = e.rootNode
        if sip.len == 0:
            sip.add(0)
        else:
            n = outlineView.itemAtIndexPath(sip).get(Node3D)

        outlineView.expandRow(sip)
        discard n.newChild("New Node")
        sip.add(n.children.len - 1)
        outlineView.reloadData()
        outlineView.selectItemAtIndexPath(sip)
    result.addSubview(createNodeButton)

    let deleteNodeButton = Button.new(newRect(24, result.bounds.height - 20, 20, 20))
    # deleteNodeButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    deleteNodeButton.title = "-"
    deleteNodeButton.onAction do():
        if outlineView.selectedIndexPath.len != 0:
            let n = outlineView.itemAtIndexPath(outlineView.selectedIndexPath).get(Node3D)
            n.removeFromParent()
            var sip = outlineView.selectedIndexPath
            sip.delete(sip.len-1)
            outlineView.selectItemAtIndexPath(sip)
            outlineView.reloadData()
    result.addSubview(deleteNodeButton)

    let refreshButton = Button.new(newRect(46, result.bounds.height - 20, 60, 20))
    # refreshButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
    refreshButton.title = "Refresh"
    refreshButton.onAction do():
        outlineView.reloadData()
    result.addSubview(refreshButton)

    when not defined(android) and not defined(ios):
        let loadButton = Button.new(newRect(110, result.bounds.height - 20, 60, 20))
        # loadButton.autoresizingMask = { afFlexibleMinY, afFlexibleMaxX }
        loadButton.title = "Load"
        loadButton.onAction do():
            when defined(js):
                alert("Loading is currenlty availble in native version only.")
            else:
                var sip = outlineView.selectedIndexPath
                var p = e.rootNode
                if sip.len == 0:
                    sip.add(0)
                else:
                    p = outlineView.itemAtIndexPath(sip).get(Node3D)

                outlineView.expandRow(sip)
                let path = callDialogFileOpen("Select file")
                loadSceneAsync path, proc(n: Node) =
                    p.addChild(n)
                    outlineView.reloadData()
        result.addSubview(loadButton)

proc startEditingNodeInView*(n: Node3D, v: View): Editor =
    result.new()
    result.rootNode = n

    let inspectorView = InspectorView.new(newRect(200, 0, 240, 700))
    result.treeView = newTreeView(result, inspectorView)
    v.window.addSubview(result.treeView)
    v.window.addSubview(inspectorView)

proc endEditing*(e: Editor) =
    discard
