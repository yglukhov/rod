import strutils, tables
import nimx.view
import nimx.text_field
import nimx.button
import nimx.matrixes
import nimx.menu
import nimx.scroll_view
import nimx.panel_view
import nimx.linear_layout
import nimx.property_visitor

import variant

export view

import node
import component
import rod_types

import rod.property_editors.propedit_registry
import rod.property_editors.standard_editors


type InspectorView* = ref object of PanelView

method init*(i: InspectorView, r: Rect) =
    procCall i.PanelView.init(r)
    i.collapsible = true
    i.collapsed = true
    let title = newLabel(newRect(22, 6, 96, 15))
    title.textColor = whiteColor()
    title.text = "Properties"
    i.addSubview(title)
    i.autoresizingMask = { afFlexibleMaxX }

proc newSectionTitle(inspector: InspectorView, n: Node3D, name: string): View
proc createNewComponentButton(inspector: InspectorView, n: Node3D): View

proc moveSubviewToBack(v, s: View) =
    let i = v.subviews.find(s)
    if i != -1:
        v.subviews.delete(i)
        v.subviews.insert(s, 0)

proc `inspectedNode=`*(i: InspectorView, n: Node3D) =
    # TODO: This is a hacky hardcode! Here we assume that inspector can have either
    # 2 subviews (no node edited) or 3 subviews, first of which is the scrollview
    # with property editors. We want to remove the scrollview.
    if i.subviews.len > 2:
        i.subviews[0].removeFromSuperview()

    if not n.isNil:
        let propView = newVerticalLayout(newRect(0, 0, i.bounds.width, 20))
        propView.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        propView.topMargin = 5
        propView.bottomMargin = 5
        propView.leftMargin = 5
        propView.rightMargin = 5

        proc changeInspectorView() =
            i.inspectedNode = n

        proc cahngeInspectorView() =
            i.inspectedNode = n

        var visitor : PropertyVisitor
        visitor.requireName = true
        visitor.requireSetter = true
        visitor.requireGetter = true
        visitor.flags = { pfEditable }
        visitor.commit = proc() =
            propView.addSubview(propertyEditorForProperty(n, visitor.name, visitor.setterAndGetter, visitor.onChangeCallback, changeInspectorView))

        n.visitProperties(visitor)

        if not n.components.isNil:
            for k, v in n.components:
                propView.addSubview(newSectionTitle(i, n, k))
                v.visitProperties(visitor)

        propView.addSubview(createNewComponentButton(i, n))

        var fs = propView.frame.size

        i.contentHeight = if fs.height + i.titleHeight + i.frame.y <= i.window.frame.height: fs.height else: i.window.frame.height - i.titleHeight - i.frame.y
        i.collapsed = false

        let scView = newScrollView(propView)
        scView.horizontalScrollBar = nil
        scView.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}
        scView.setFrameOrigin(newPoint(scView.frame.x, i.titleHeight))
        scView.setFrameSize(newSize(i.frame.width, i.contentHeight))
        i.addSubview(scView)
        i.moveSubviewToBack(scView)
    else:
        i.collapsed = true

proc newSectionTitle(inspector: InspectorView, n: Node3D, name: string): View =
    result = View.new(newRect(0, 0, 324, 18))
    let v = newLabel(newRect(100, 0, 100, 15))
    v.text = name
    v.textColor = newColor(1.0, 1.0, 0.5)
    result.addSubview(v)

    let removeButton = newButton(newRect(result.bounds.width - 18, 0, 18, 18))
    removeButton.autoresizingMask = {afFlexibleMinX, afFlexibleMinY}
    removeButton.title = "-"
    removeButton.onAction do():
        n.removeComponent(name)
        inspector.inspectedNode = n
    result.addSubview(removeButton)

proc createNewComponentButton(inspector: InspectorView, n: Node3D): View =
    let b = Button.new(newRect(0, 30, 0, 20))
    b.title = "New component"
    b.onAction do():
        var menu : Menu
        menu.new()
        var items = newSeq[MenuItem]()
        for i, c in registeredComponents():
            closureScope:
                let menuItem = newMenuItem(c)
                menuItem.action = proc() =
                    discard n.component(menuItem.title)
                    inspector.inspectedNode = n
                items.add(menuItem)

        menu.items = items
        menu.popupAtPoint(inspector, newPoint(0, 27))
    result = b
