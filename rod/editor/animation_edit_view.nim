import sequtils, intsets, tables
import nimx.view, nimx.table_view, nimx.scroll_view, nimx.button, nimx.text_field
import nimx.menu, nimx.event, nimx.property_visitor
import variant

import animation_chart_view, animation_curves_edit_view, dopesheet_view
import animation_editor_types

import rod.node, rod.component

type SplitView* = ref object of View

registerClass(SplitView)

const leftPaneWidth = 200

type
    EditedProperty* = object
        name: string
        curve: AnimationCurve
        sng: Variant

    AnimationEditView* = ref object of View
        curveEditView: AnimationCurvesEditView
        dopesheetView: DopesheetView
        propertyTableView: TableView
        editedProperties: seq[EditedProperty]
        mCurveEditingMode: bool
        mEditedNode*: Node

proc `editedNode=`*(v: AnimationEditView, n: Node) =
    v.mEditedNode = n

proc findAnimatableProperty(n: Node, propName: string): Variant =
    var res : Variant
    var visitor : PropertyVisitor
    visitor.requireName = true
    visitor.requireSetter = true
    visitor.requireGetter = true
    visitor.flags = { pfAnimatable }
    visitor.commit = proc() =
        if res.isEmpty:
            if visitor.name == propName:
                res = visitor.setterAndGetter

    n.visitProperties(visitor)

    if res.isEmpty and not n.components.isNil:
        for k, v in n.components:
            v.visitProperties(visitor)
            if not res.isEmpty: break

    result = res

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

proc addEditedProperty(v: AnimationEditView, name: string) =
    var ep: EditedProperty
    ep.name = name
    ep.curve = newAnimationCurve()
    ep.curve.color = colors[v.editedProperties.len mod colors.len]
    ep.sng = findAnimatableProperty(v.mEditedNode, name)
    v.editedProperties.add(ep)
    v.propertyTableView.reloadData()
    var curves = newSeq[AnimationCurve]()
    for p in v.editedProperties: curves.add(p.curve)
    v.dopesheetView.curves = curves

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
        let sng = ep.sng.get(SetterAndGetter[Coord])
        if ep.curve.keys.len > 1:
            sng.setter(ep.curve.valueAtPos(pos))

method init*(v: AnimationEditView, r: Rect) =
    procCall v.View.init(r)
    v.editedProperties = @[]

    let mainSplitView = SplitView.new(v.bounds)
    mainSplitView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.addSubview(mainSplitView)

    const topPanelHeight = 25
    const bottomPanelHeight = 25

    let leftPaneView = View.new(newRect(0, 0, leftPaneWidth, v.bounds.height))
    let playButton = Button.new(newRect(0, 0, 50, topPanelHeight))
    playButton.title = "Play"
    leftPaneView.addSubview(playButton)
    leftPaneView.autoresizingMask = {afFlexibleMaxX, afFlexibleHeight}

    v.propertyTableView = TableView.new(newRect(0, topPanelHeight, 200, leftPaneView.bounds.height - topPanelHeight - bottomPanelHeight))
    v.propertyTableView.autoresizingMask = {afFlexibleMaxX, afFlexibleHeight}
    let s = newScrollView(v.propertyTableView)
    s.autoresizingMask = {afFlexibleMaxX, afFlexibleHeight}
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
        let sng = ep.sng.get(SetterAndGetter[Coord])
        ep.curve.addKey(cursorPos, sng.getter())
    v.setNeedsDisplay()

method onKeyDown*(v: AnimationEditView, e: var Event): bool =
    if e.keyCode == VirtualKey.K:
        v.insertKeyframeAtCurPos()
        result = true

registerClass(AnimationEditView)
