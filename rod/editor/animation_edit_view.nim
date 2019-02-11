import sequtils, intsets, tables, logging
import nimx.view, nimx.table_view, nimx.scroll_view, nimx.button, nimx.text_field
import nimx.popup_button, nimx.window, nimx.linear_layout
import nimx.menu, nimx.event, nimx.property_visitor
import variant

import animation_chart_view, animation_curves_edit_view, dopesheet_view
import animation_editor_types

import rod.node, rod.component
import rod.animation.property_animation
import rod.animation.animation_sampler

import rod.edit_view

const leftPaneWidth = 200

type
    EditedProperty* = object
        name: string
        curve: AbstractAnimationCurve
        sng: Variant

    AnimationEditView* = ref object of EditorTabView
        curveEditView: AnimationCurvesEditView
        dopesheetView: DopesheetView
        propertyTableView: TableView
        editedProperties: seq[EditedProperty]
        mCurveEditingMode: bool
        mEditedNode: Node
        animationSelector*: PopupButton
        mEditedAnimation*: PropertyAnimation

proc `editedNode=`*(v: AnimationEditView, n: Node) =
    v.mEditedNode = n
    var items = newSeq[string]()
    if not v.mEditedNode.isNil and not v.mEditedNode.animations.isNil:
        for k, v in v.mEditedNode.animations:
            items.add(k)
    v.animationSelector.items = items
    v.animationSelector.sendAction()

proc currentLeftPaneView(v: AnimationEditView): AnimationChartView =
    if v.mCurveEditingMode:
        v.curveEditView
    else:
        v.dopesheetView

template curveEditingMode(v: AnimationEditView): bool = v.mCurveEditingMode
proc `curveEditingMode=`(v: AnimationEditView, flag: bool) =
    if v.mCurveEditingMode != flag:
        let fromView = v.currentLeftPaneView
        fromView.removeFromSuperview()
        v.mCurveEditingMode = flag
        let splitView = v.subviews[0]
        let toView = v.currentLeftPaneView
        toView.setFrame(newRect(leftPaneWidth, 0, splitView.bounds.width - leftPaneWidth, splitView.bounds.height))
        toView.fromX = fromView.fromX
        toView.toX = fromView.toX
        toView.cursorPos = fromView.cursorPos
        splitView.addSubview(toView)

let colors = [
    newColor(1, 0, 0),
    newColor(0, 1, 0),
    newColor(0, 0, 1),
    newColor(0, 1, 1),
    newColor(1, 0, 1)
]

proc updateDopesheetCurves(v: AnimationEditView) =
    var curves = newSeq[AbstractAnimationCurve]()
    for p in v.editedProperties: curves.add(p.curve)
    v.dopesheetView.curves = curves

proc addEditedProperty(v: AnimationEditView, name: string) =
    var ep: EditedProperty
    var ap: AnimatedProperty
    ep.sng = findAnimatablePropertyForSubtree(v.mEditedNode, "", -1, name)
    ep.name = name
    ap.new()
    ap.propName = name
    template createCurve(T: typedesc): typed =
        ep.curve = newAnimationCurve[T]()
    template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
    switchAnimatableTypeId(ep.sng.typeId, getSetterAndGetterTypeId, createCurve)

    ap.sampler = ep.curve.getSampler()
    ap.progressSetter = makeProgressSetter(ep.sng, ap.sampler)

    ep.curve.color = colors[v.editedProperties.len mod colors.len]
    v.editedProperties.add(ep)
    if not v.mEditedAnimation.isNil:
        v.mEditedAnimation.animatedProperties.add(ap)
    v.propertyTableView.reloadData()
    v.updateDopesheetCurves()

proc createAddPropertyButton(v: AnimationEditView): Button =
    let b = Button.new(zeroRect)
    b.title = "+"
    b.onAction do():
        if not v.mEditedNode.isNil:
            var menu : Menu
            menu.new()
            var items = newSeq[MenuItem]()
            let props = @["tX", "tY", "tZ"]
            for i, p in props:
                closureScope:
                    let prop = p
                    let menuItem = newMenuItem(prop)
                    menuItem.action = proc() =
                        v.addEditedProperty(prop)
                    items.add(menuItem)
            menu.items = items
            menu.popupAtPoint(b, newPoint(0, 27))
    result = b

proc onCursorPosChange(v: AnimationEditView, pos: float) =
    for ep in v.editedProperties:
        ep.curve.applyValueAtPosToSetter(pos, ep.sng)

proc `editedAnimation=`(v: AnimationEditView, a: PropertyAnimation) =
    v.mEditedAnimation = a
    v.editedProperties = @[]
    if not a.isNil:
        for ap in a.animatedProperties:
            var ep: EditedProperty
            ep.name = ap.propName
            try:
                ep.sng = findAnimatablePropertyForSubtree(v.mEditedNode, ap.nodeName, ap.compIndex, ap.propName)
                template createCurve(T: typedesc): typed =
                    if ap.sampler of BezierKeyFrameAnimationSampler[T]:
                        ep.curve = newAnimationCurve[T](BezierKeyFrameAnimationSampler[T](ap.sampler))
                    else:
                        ep.curve = newAnimationCurve[T]()
                template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
                switchAnimatableTypeId(ep.sng.typeId, getSetterAndGetterTypeId, createCurve)
                ep.curve.color = colors[v.editedProperties.len mod colors.len]
                v.editedProperties.add(ep)
            except:
                error "Could not attach animatable property: ", getCurrentExceptionMsg()
    v.propertyTableView.reloadData()
    v.updateDopesheetCurves()

const topPanelHeight = 25
const bottomPanelHeight = 25

proc createPlayButton(v: AnimationEditView): Button =
    result = Button.new(newRect(0, 0, 50, topPanelHeight))
    result.title = "Play"
    var currentlyPlayingAnimation: Animation
    let b = result
    result.onAction do():
        if not currentlyPlayingAnimation.isNil:
            currentlyPlayingAnimation.cancel()
            currentlyPlayingAnimation = nil
            b.title = "Play"
        elif v.animationSelector.selectedIndex >= 0 and not v.mEditedNode.isNil:
            let a = v.mEditedNode.animationNamed(v.animationSelector.selectedItem, true)
            if not a.isNil:
                currentlyPlayingAnimation = a
                a.onComplete do():
                    b.title = "Play"
                    currentlyPlayingAnimation = nil
                v.window.addAnimation(a)
                b.title = "Stop"

method init*(v: AnimationEditView, r: Rect) =
    procCall v.View.init(r)
    v.editedProperties = @[]

    let mainSplitView = newHorizontalLayout(v.bounds)
    mainSplitView.userResizeable = true
    mainSplitView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.addSubview(mainSplitView)

    let leftPaneView = View.new(newRect(0, 0, leftPaneWidth, v.bounds.height))
    let playButton = v.createPlayButton()
    leftPaneView.addSubview(playButton)
    leftPaneView.autoresizingMask = { afFlexibleMaxX, afFlexibleHeight }

    v.animationSelector = PopupButton.new(newRect(52, 0, leftPaneView.bounds.width - 52, topPanelHeight))
    v.animationSelector.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
    leftPaneView.addSubview(v.animationSelector)
    v.animationSelector.onAction do():
        if v.animationSelector.selectedIndex >= 0:
            let a = v.mEditedNode.animationNamed(v.animationSelector.selectedItem, true)
            if a of PropertyAnimation:
                v.editedAnimation = PropertyAnimation(a)
            else:
                v.editedAnimation = nil
        else:
            v.editedAnimation = nil

    v.propertyTableView = TableView.new(newRect(0, topPanelHeight, leftPaneWidth, leftPaneView.bounds.height - topPanelHeight - bottomPanelHeight))
    v.propertyTableView.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}
    let s = newScrollView(v.propertyTableView)
    leftPaneView.addSubview(s)
    mainSplitView.addSubview(leftPaneView)

    v.propertyTableView.numberOfRows = proc(): int =
        v.editedProperties.len

    v.propertyTableView.createCell = proc (): TableViewCell =
        result = newTableViewCell(newLabel(newRect(0, 0, 100, 20)))
    v.propertyTableView.configureCell = proc (c: TableViewCell) =
        TextField(c.subviews[0]).text = v.editedProperties[c.row].name

    v.propertyTableView.onSelectionChange = proc() =
        let selectedRows = toSeq(items(v.propertyTableView.selectedRows))
        if selectedRows.len > 0:
            v.curveEditView.curves = @[v.editedProperties[selectedRows[0]].curve]
        else:
            v.curveEditView.curves = @[]

    v.propertyTableView.defaultRowHeight = 20

    let addPropertyButton = v.createAddPropertyButton()
    addPropertyButton.setFrame(newRect(0, leftPaneView.bounds.maxY - bottomPanelHeight, 25, bottomPanelHeight))
    addPropertyButton.autoresizingMask = { afFlexibleMaxX, afFlexibleMinY }
    leftPaneView.addSubview(addPropertyButton)

    let removePropertyButton = Button.new(newRect(25, leftPaneView.bounds.maxY - bottomPanelHeight, 25, bottomPanelHeight))
    removePropertyButton.title = "-"
    removePropertyButton.autoresizingMask = { afFlexibleMaxX, afFlexibleMinY }
    removePropertyButton.onAction do():
        let selectedRows = toSeq(items(v.propertyTableView.selectedRows))
        if selectedRows.len > 0:
            v.editedProperties.delete(selectedRows[0])
            v.propertyTableView.reloadData()

    leftPaneView.addSubview(removePropertyButton)

    let toggleCurveModeButton = Button.new(newRect(leftPaneView.bounds.maxX - 25, leftPaneView.bounds.maxY - bottomPanelHeight, 25, bottomPanelHeight))
    toggleCurveModeButton.title = "o"
    toggleCurveModeButton.autoresizingMask = { afFlexibleMinX, afFlexibleMinY }
    leftPaneView.addSubview(toggleCurveModeButton)
    toggleCurveModeButton.onAction do():
        v.curveEditingMode = not v.curveEditingMode

    v.curveEditView = AnimationCurvesEditView.new(newRect(0, 0, 100, 100))
    v.curveEditView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.curveEditView.onCursorPosChange = proc() =
        v.onCursorPosChange(v.curveEditView.cursorPos)
    v.dopesheetView = DopesheetView.new(newRect(0, 0, 100, 100))
    v.dopesheetView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.dopesheetView.onCursorPosChange = proc() =
        v.onCursorPosChange(v.dopesheetView.cursorPos)

    v.mCurveEditingMode = true
    v.curveEditingMode = false

method acceptsFirstResponder*(v: AnimationEditView): bool = true

proc insertKeyframeAtCurPos(v: AnimationEditView) =
    let cursorPos = v.currentLeftPaneView.cursorPos
    for ep in v.editedProperties:
        ep.curve.addKeyAtPosWithValueFromGetter(cursorPos, ep.sng)
    v.setNeedsDisplay()

method onKeyDown*(v: AnimationEditView, e: var Event): bool =
    if e.keyCode == VirtualKey.K:
        v.insertKeyframeAtCurPos()
        result = true

method tabSize*(v: AnimationEditView, bounds: Rect): Size=
    result = newSize(bounds.width, 150.0)

method tabAnchor*(v: AnimationEditView): EditorTabAnchor =
    result = etaBottom

method setEditedNode*(v: AnimationEditView, n: Node)=
    v.editedNode = n

registerEditorTab("Animation", AnimationEditView)
