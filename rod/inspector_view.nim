import algorithm
import strutils, tables
import nimx.view
import nimx.text_field
import nimx.button
import nimx.menu
import nimx.scroll_view
import nimx.linear_layout
import nimx.property_visitor
import nimx.expanding_view
import nimx.stack_view

import variant

export view

import node
import component
import rod_types

import rod.property_editors.propedit_registry
import rod.property_editors.standard_editors


const componentsViewSize = newSize(200, 300)

type InspectorView* = ref object of View

method init*(i: InspectorView, r: Rect) =
    procCall i.View.init(r)
    i.resizingMask = "wh"

proc createComponentsView(inspector: InspectorView, n: Node)

proc `inspectedNode=`*(i: InspectorView, n: Node3D) =
    # TODO: This is a hacky hardcode! Here we assume that inspector can have either
    # 2 subviews (no node edited) or 3 subviews, first of which is the scrollview
    # with property editors. We want to remove the scrollview.
    if i.subviews.len > 0:
        i.subviews[0].removeFromSuperview()

    if not n.isNil:
        let propView = newVerticalLayout(newRect(0, 0, i.bounds.width, 20))
        propView.resizingMask = "wb"
        propView.topMargin = 5
        propView.bottomMargin = 5
        propView.leftMargin = 5
        propView.rightMargin = 5

        proc changeInspectorView() =
            i.inspectedNode = n

        var expView= newExpandingView(newRect(0, 0, 328, 20.0))
        expView.title = "Node"
        expView.expand()

        var visitor : PropertyVisitor
        visitor.requireName = true
        visitor.requireSetter = true
        visitor.requireGetter = true
        visitor.flags = { pfEditable }
        visitor.commit = proc() =
            expView.addContent(propertyEditorForProperty(n, visitor.name, visitor.setterAndGetter, visitor.onChangeCallback, changeInspectorView))

        n.visitProperties(visitor)
        propView.addSubview(expView)

        if not n.components.isNil:
            for v in n.components:
                expView = newExpandingView(newRect(0, 0, 328, 20.0))
                expView.title = v.className
                expView.expand()

                let removeButton = newButton(expView, newPoint(328 - 18, 0), newSize(18.0, 18), "-")
                removeButton.autoresizingMask = {afFlexibleMinX}
                removeButton.onAction do():
                    n.removeComponent(v.className)
                    i.inspectedNode = n

                v.visitProperties(visitor)
                propView.addSubview(expView)

        let newComponentButtn = Button.new(newRect(0, 30, 0, 20))
        newComponentButtn.title = "New component"
        newComponentButtn.onAction do():
            createComponentsView(i, n)

        propView.addSubview(newComponentButtn)

        let scView = newScrollView(propView)
        scView.horizontalScrollBar = nil
        scView.resizingMask = "wh"
        scView.setFrame(i.bounds)
        i.addSubview(scView)
    else:
        discard


proc createComponentButtons(inspector: InspectorView, n: Node3D, components_list: seq[string]): StackView =
        var menu = newStackView(newRect(0, 0, componentsViewSize.width, 100))
        var components = components_list
        sort(components, system.cmp)
        for i, c in components:
            closureScope:
                let compName = c
                let createButton = newButton(menu, newPoint(0, 0), newSize(componentsViewSize.width - 20.0, 16), compName)
                createButton.onAction do():
                    discard n.component(compName)
                    inspector.inspectedNode = n

        result = menu

proc createComponentsView(inspector: InspectorView, n: Node) =
    let stackView = newStackView(newRect(0, 0, componentsViewSize.width, 400))
    var isFirst = true
    for key, value in componentGroupsTable:
        let expView = newExpandingView(newRect(0, 0, componentsViewSize.width, 20.0), true)
        expView.title = key
        stackView.addSubview(expView)
        expView.addContent(inspector.createComponentButtons(n, value))

        if isFirst:
            isFirst = false
            let createButton = newButton(expView, newPoint(componentsViewSize.width - 20, 0), newSize(16.0, 16), "X")
            createButton.onAction do():
                stackView.removeFromSuperview()

    # stackView.popupAtPoint(inspector, newPoint(-205, 0))
    var origin = inspector.convertPointToWindow(newPoint(-205, 0))
    stackView.setFrameOrigin(origin)
    inspector.window.addSubview(stackView)


