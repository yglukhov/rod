import strutils, tables
import nimx.view
import nimx.text_field
import nimx.button
import nimx.matrixes
import nimx.menu
import nimx.scroll_view

import variant

export view

import panel_view
import node
import component
import rod_types

import property_visitor
import property_editors.propedit_registry
import property_editors.standard_editors

type InspectorView* = ref object of PanelView
    nameTextField: TextField

method init*(i: InspectorView, r: Rect) =
    procCall i.PanelView.init(r)
    i.collapsible = true
    i.collapsed = true
    let title = newLabel(newRect(22, 6, 96, 15))
    title.textColor = whiteColor()
    title.text = "Properties"
    i.addSubview(title)
    i.autoresizingMask = { afFlexibleMaxX }

proc newSectionTitle(y: Coord, inspector: InspectorView, n: Node3D, name: string): View
proc createNewComponentButton(y: Coord, inspector: InspectorView, n: Node3D): View

proc `inspectedNode=`*(i: InspectorView, n: Node3D) =
    if i.subviews.len > 1:
        i.subviews[1].removeFromSuperview()

    if not n.isNil:
        let propView = View.new(newRect(1, 29, i.bounds.width - 6, i.bounds.height - 40))
        propView.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}

        var y = Coord(0)
        var pv: View
        var visitor : PropertyVisitor
        visitor.requireName = true
        visitor.requireSetter = true
        visitor.requireGetter = true
        visitor.flags = { pfEditable }
        visitor.commit = proc() =
            pv = propertyEditorForProperty(n, visitor.name, visitor.setterAndGetter)
            pv.setFrameOrigin(newPoint(6, y))
            pv.setFrameSize(newSize(pv.frame.width - 16.Coord, pv.frame.height))
            y += pv.frame.height
            propView.addSubview(pv)

        n.visitProperties(visitor)

        if not n.components.isNil:
            for k, v in n.components:
                y += 12
                pv = newSectionTitle(y, i, n, k)
                y += pv.frame.height
                propView.addSubview(pv)
                v.visitProperties(visitor)

        pv = createNewComponentButton(y, i, n)
        pv.setFrameSize(newSize(pv.frame.width - 16, pv.frame.height))
        y += pv.frame.height
        propView.addSubview(pv)

        var fs = propView.frame.size
        fs.height = y + 79
        propView.setFrameSize(fs)
        i.addSubview(propView)

        i.fullHeight = if fs.height < 600: fs.height else: 600
        i.setFrameSize(newSize(i.frame.size.width, if i.collapsed: 27.Coord else: i.fullHeight))

        if i.collapsible:
            if i.collapsed:
                i.collapsed = false
                i.fullHeight = if fs.height < 600: fs.height else: 600
                i.setFrameSize(newSize(i.frame.size.width, if i.collapsed: 27.Coord else: i.fullHeight))
                i.setNeedsDisplay()

        let scPos = newPoint(6, 27)
        i.subviews[1].setFrameOrigin(scPos)
        let scView = newScrollView(i.subviews[1])
        scView.setFrameSize(newSize(i.frame.size.width - 6, i.frame.height - 27))
        i.addSubview(scView)

    else:
        if i.collapsible:
            if not i.collapsed:
                i.collapsed = true
                i.setFrameSize(newSize(i.frame.size.width, if i.collapsed: 27.Coord else: i.fullHeight))
                i.setNeedsDisplay()

proc newSectionTitle(y: Coord, inspector: InspectorView, n: Node3D, name: string): View =
    result = View.new(newRect(0, y, 324, 17))
    let v = newLabel(newRect(120, 0, 100, 15))
    v.text = name
    v.textColor = newColor(1.0, 1.0, 0.5)
    result.addSubview(v)

    let removeButton = newButton(newRect(result.bounds.width - 40, -2, 24, 24))
    removeButton.autoresizingMask = {afFlexibleMinX, afFlexibleMaxY}
    removeButton.title = "-"
    removeButton.onAction do():
        n.removeComponent(name)
        inspector.inspectedNode = n
    result.addSubview(removeButton)

proc createNewComponentButton(y: Coord, inspector: InspectorView, n: Node3D): View =
    let b = Button.new(newRect(6, y + 24, inspector.frame.width - 12, 24))
    b.title = "New component"
    b.onAction do():
        var menu : Menu
        menu.new()
        var items = newSeq[MenuItem]()
        for i, c in registeredComponents():
            let menuItem = newMenuItem(c)
            let pWorkaroundForJS = proc(mi: MenuItem): proc() =
                result = proc() =
                    discard n.component(mi.title)
                    inspector.inspectedNode = n

            menuItem.action = pWorkaroundForJS(menuItem)
            items.add(menuItem)

        menu.items = items
        menu.popupAtPoint(inspector, newPoint(0, 27))
    result = b
