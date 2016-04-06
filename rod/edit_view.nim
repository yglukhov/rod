import math

import nimx.view
import nimx.types
import nimx.button

import node
import panel_view
import outline_view
import inspector_view
import rod_types

import nimx.animation
import nimx.color_picker
import nimx.context
import nimx.portable_gl
import nimx.scroll_view
import nimx.text_field
import nimx.table_view_cell

import rod.scene_composition
import rod.component.mesh_component
import rod.component.node_selector

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

proc focusOnNode*(cameraNode: node.Node, focusNode: node.Node) =
    let distance = 100.Coord
    cameraNode.translation = newVector3(
        focusNode.translation.x,
        focusNode.translation.y,
        focusNode.translation.z + distance
    )

proc newSettingsView(e: Editor, r: Rect): PanelView =
    result = PanelView.new(r)
    result.collapsible = true

    let title = newLabel(newRect(22, 6, 108, 15))
    title.textColor = whiteColor()
    title.text = "Editor Settings"

    result.addSubview(title)

    var y: Coord = 36
    let bgColorLabel = newLabel(newRect(6, y, 50, 20))
    bgColorLabel.textColor = newGrayColor(0.78)
    bgColorLabel.text = "Background:"

    result.addSubview(bgColorLabel)

    let bgColorButton = newButton(result, newPoint(102, y), newSize(40, 20), "...")
    let pv = result
    bgColorbutton.onAction do():
        let cPicker = newColorPickerView(newRect(0, 0, 300, 200))
        cPicker.onColorSelected = proc(c: Color) =
            currentContext().gl.clearColor(c.r, c.g, c.b, c.a)
            cPicker.removeFromSuperview()
        cPicker.setFrameOrigin(newPoint(pv.frame.x - 300, pv.frame.y))
        pv.window.addSubview(cPicker)

    y += bgColorLabel.frame.height + 6

    let cameraFocusButton = newButton(result, newPoint(6, y), newSize(120, 20), "Zoom Selection")
    y += 26
    cameraFocusButton.onAction do():
        if not e.selectedNode.isNil:
            let cam = e.rootNode.findNode("camera")
            if not cam.isNil:
                e.rootNode.findNode("camera").focusOnNode(e.selectedNode)
    result.addSubview(cameraFocusButton)

proc newTreeView(e: Editor, inspector: InspectorView): PanelView =
    result = PanelView.new(newRect(0, 0, 200, 700))
    result.collapsible = true

    let title = newLabel(newRect(22, 6, 108, 15))
    title.textColor = whiteColor()
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

        if not n.isNil:
            if not e.selectedNode.isNil and e.selectedNode.componentIfAvailable(LightSource).isNil:
                e.selectedNode.removeComponent(NodeSelector)
                if e.selectedNode != n:
                    e.selectedNode = n
                    discard e.selectedNode.component(NodeSelector)
            else:
                e.selectedNode = n
                discard e.selectedNode.component(NodeSelector)

        inspector.inspectedNode = n

    outlineView.reloadData()

    let outlineScrollView = newScrollView(outlineView)
    outlineScrollView.setFrameSize(newSize(outlineScrollView.frame.size.width, outlineScrollView.frame.size.height - 7))
    result.addSubview(outlineScrollView)

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
                if not isNil(path) and path != "":
                    loadSceneAsync path, proc(n: Node) =
                        p.addChild(n)
                        outlineView.reloadData()
        result.addSubview(loadButton)

proc startEditingNodeInView*(n: Node3D, v: View): Editor =
    result.new()
    result.rootNode = n

    let inspectorView = InspectorView.new(newRect(200, 0, 340, 700))
    let settingsView = result.newSettingsView(newRect(v.window.bounds.width - 200, v.window.bounds.height - 200, 200, 200))

    result.treeView = newTreeView(result, inspectorView)
    v.window.addSubview(result.treeView)

    v.window.addSubview(inspectorView)
    v.window.addSubview(settingsView)

proc endEditing*(e: Editor) =
    discard
