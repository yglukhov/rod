import nimx/[view, text_field, button, 
    scroll_view, linear_layout, slider, property_visitor,
    expanding_view, stack_view
]

import rod/property_editors/[propedit_registry, standard_editors]
import rod/[node, component, rod_types]
import rod/edit_view
import rod/editor/animation/editor_animation_view
import algorithm, tables
import variant


export view


const componentsViewSize = newSize(200, 300)

type InspectorView* = ref object of EditorTabView
    propView: LinearLayout
    scView: ScrollView
    currNode: Node
    autoUpdate: bool

method init*(i: InspectorView, r: Rect) =
    procCall i.View.init(r)
    i.resizingMask = "wh"

    let autoVisitView = newView(newRect(0.0, 0.0, i.bounds.width, 20.0))
    autoVisitView.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    autoVisitView.backgroundColor = newColor(0.0, 0.0, 0.0, 0.25)

    let lbl = newLabel(newRect(0.0, 2.0, i.bounds.width - 20.0, 15.0))
    lbl.text = "Auto update:"
    lbl.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    autoVisitView.addSubview(lbl)

    var boxBtn = newCheckbox(newRect(i.bounds.width - 17.5, 2.5, 15.0, 15.0))
    boxBtn.autoresizingMask = {afFlexibleMinX, afFlexibleMaxY}
    boxBtn.onAction do():
        i.autoUpdate = boxBtn.boolValue

    autoVisitView.addSubview(boxBtn)

    i.propView = newVerticalLayout(newRect(0, 20, i.bounds.width, 20))
    i.propView.resizingMask = "wb"
    i.propView.topMargin = 5
    i.propView.bottomMargin = 5
    i.propView.leftMargin = 5
    i.propView.rightMargin = 5

    i.scView = newScrollView(i.propView)
    i.scView.horizontalScrollBar = nil
    i.scView.resizingMask = "wh"
    i.scView.setFrame(newRect(0.0, 20.0, i.bounds.width, i.bounds.height - 20.0))
    i.addSubview(i.scView)

    i.addSubView(autoVisitView)

proc createComponentsView(inspector: InspectorView, n: Node)


proc visitProperties*(i: InspectorView, c: Composition, p: var PropertyVisitor) =
    when loadingAndSavingAvailable:
        var url = relativeUrl(c.url, i.editor.currentProjectPath())
    else:
        var url = c.url
    p.visitProperty("url", url)


proc `inspectedNode=`*(i: InspectorView, n: Node) =
    # TODO: This is a hacky hardcode! Here we assume that inspector can have either
    # 2 subviews (no node edited) or 3 subviews, first of which is the scrollview
    # with property editors. We want to remove the scrollview.
    # if i.propView.subviews.len > 0:
    #     i.propView.subviews[0].removeFromSuperview()

    let scrollBar = i.scView.verticalScrollBar()
    let oldPos = scrollBar.value()

    while i.propView.subviews.len() > 0:
        i.propView.subviews[0].removeFromSuperview()

    if not n.isNil:
        i.currNode = n
        proc changeInspectorView() =
            i.inspectedNode = n

        var expView= newExpandingView(newRect(0, 20, 328, 20.0))

        var visitor : PropertyVisitor
        visitor.requireName = true
        visitor.requireSetter = true
        visitor.requireGetter = true
        if i.editor.mode == emAnimation:
            visitor.flags = { pfAnimatable }
        else:
            visitor.flags = { pfEditable }
        visitor.commit = proc() =
            let propView = propertyEditorForProperty(n, visitor.name, visitor.setterAndGetter, nil, changeInspectorView)
            propView.autoresizingMask = {afFlexibleWidth}
            let propHolder = newView(propView.frame)
            propHolder.addSubview(propView)
            
            if i.editor.mode == emAnimation:
                var btn = newButton(propView, newPoint(100 - 17, 1), newSize(16, 16), "a")
                btn.autoresizingMask = {afFlexibleMinX}

                let propName = visitor.name
                let sng = visitor.setterAndGetter
                let typId = sng.typeId
                btn.onAction do():
                    echo "hi ", propName
                    let animEditor = getEditorTab[AnimationEditView](i.editor)
                    if not animEditor.isNil:
                        animEditor.foo()

            expView.addContent(propHolder)

        if not n.composition.isNil:
            expView.title = "Composition"
            expView.expand()
            i.visitProperties(n.composition, visitor)
            
            var openComp = newButton(expView, newPoint(328 - 50, 0), newSize(50.0, 18), "open")
            openComp.autoresizingMask = {afFlexibleMinX}
            openComp.onAction do():
                i.editor.openComposition(n.composition.url)
                echo "open comp ", n.composition.url

            i.propView.addSubview(expView)

            expView= newExpandingView(newRect(0, 20, 328, 20.0))
        
        expView.title = "Node"
        expView.expand()

        n.visitProperties(visitor)
        i.propView.addSubview(expView)

        for v in n.components:
            closureScope:
                expView = newExpandingView(newRect(0, 0, 328, 20.0))
                expView.title = v.className
                # let class_name = v.className
                let component = v
                expView.expand()

                let removeButton = newButton(expView, newPoint(328 - 18, 0), newSize(18.0, 18), "-")
                removeButton.autoresizingMask = {afFlexibleMinX}
                removeButton.onAction do():
                    n.removeComponent(component)
                    i.inspectedNode = n

            v.visitProperties(visitor)
            i.propView.addSubview(expView)

        let newComponentButtn = Button.new(newRect(0, 30, 0, 20))
        newComponentButtn.title = "New component"
        newComponentButtn.onAction do():
            createComponentsView(i, n)

        i.propView.addSubview(newComponentButtn)

        scrollBar.value = oldPos
        scrollBar.sendAction()
    else:
        discard


proc createComponentButtons(inspector: InspectorView, components_list: seq[string]): StackView =
    var menu = newStackView(newRect(0, 0, componentsViewSize.width, 100))
    var components = components_list
    sort(components, system.cmp)
    for i, c in components:
        closureScope:
            let compName = c
            let createButton = newButton(menu, newPoint(0, 0), newSize(componentsViewSize.width - 20.0, 16), compName)
            createButton.onAction do():
                discard inspector.currNode.addComponent(compName)
                inspector.inspectedNode = inspector.currNode

    result = menu

proc createComponentsView(inspector: InspectorView, n: Node) =
    let stackView = newStackView(newRect(0, 20, componentsViewSize.width, 400))
    var isFirst = true
    for key, value in componentGroupsTable:
        let expView = newExpandingView(newRect(0, 0, componentsViewSize.width, 20.0), true)
        expView.title = key
        stackView.addSubview(expView)
        expView.addContent(inspector.createComponentButtons(value))

        if isFirst:
            isFirst = false
            let createButton = newButton(expView, newPoint(componentsViewSize.width - 20, 0), newSize(16.0, 16), "X")
            createButton.onAction do():
                stackView.removeFromSuperview()

    var origin = inspector.convertPointToWindow(newPoint(-205, 0))
    stackView.setFrameOrigin(origin)
    inspector.window.addSubview(stackView)

method setEditedNode*(v: InspectorView, n: Node)=
    v.inspectedNode = n

method tabSize*(v: InspectorView, bounds: Rect): Size=
    result = newSize(300.0, bounds.height)

method tabAnchor*(v: InspectorView): EditorTabAnchor =
    result = etaRight

method update*(v: InspectorView)=
    if v.autoUpdate:
        v.inspectedNode = v.currNode

method onCompositionChanged*(v: InspectorView, comp: CompositionDocument) =
    # v.inspectedNode = comp.rootNode
    v.setEditedNode(comp.selectedNode)

registerEditorTab("Inspector", InspectorView)
