import nimx.view, nimx.table_view, nimx.scroll_view, nimx.button, nimx.text_field

import animation_curves_edit_view, dopesheet_view

type SplitView* = ref object of View

const leftPaneWidth = 200

type AnimationEditView* = ref object of View
    curveEditView: AnimationCurvesEditView
    dopesheetView: DopesheetView
    editedProperties: seq[string]
    mCurveEditingMode: bool

proc currentLeftPaneView(v: AnimationEditView): View =
    if v.mCurveEditingMode:
        v.curveEditView
    else:
        v.dopesheetView

template curveEditingMode(v: AnimationEditView): bool = v.mCurveEditingMode
proc `curveEditingMode=`(v: AnimationEditView, flag: bool) =
    if v.mCurveEditingMode != flag:
        v.currentLeftPaneView.removeFromSuperview()
        v.mCurveEditingMode = flag
        let splitView = v.subviews[0]
        let nv = v.currentLeftPaneView
        nv.setFrame(newRect(leftPaneWidth, 0, splitView.bounds.width - leftPaneWidth, splitView.bounds.height))
        splitView.addSubview(nv)

method init*(v: AnimationEditView, r: Rect) =
    procCall v.View.init(r)
    v.editedProperties = @["tX", "tY"]

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

    let propertyTableView = TableView.new(newRect(0, topPanelHeight, 200, leftPaneView.bounds.height - topPanelHeight - bottomPanelHeight))
    propertyTableView.autoresizingMask = {afFlexibleMaxX, afFlexibleHeight}
    let s = newScrollView(propertyTableView)
    s.autoresizingMask = {afFlexibleMaxX, afFlexibleHeight}
    leftPaneView.addSubview(s)
    mainSplitView.addSubview(leftPaneView)

    propertyTableView.numberOfRows = proc(): int =
        v.editedProperties.len

    propertyTableView.createCell = proc (): TableViewCell =
        result = newTableViewCell(newLabel(newRect(0, 0, 100, 20)))
    propertyTableView.configureCell = proc (c: TableViewCell) =
        TextField(c.subviews[0]).text = v.editedProperties[c.row]
    propertyTableView.defaultRowHeight = 20

    let addPropertyButton = Button.new(newRect(0, leftPaneView.bounds.maxY - bottomPanelHeight, 25, bottomPanelHeight))
    addPropertyButton.title = "+"
    addPropertyButton.autoresizingMask = { afFlexibleMaxX, afFlexibleMinY }
    leftPaneView.addSubview(addPropertyButton)

    let toggleCurveModeButton = Button.new(newRect(leftPaneView.bounds.maxX - 25, leftPaneView.bounds.maxY - bottomPanelHeight, 25, bottomPanelHeight))
    toggleCurveModeButton.title = "o"
    toggleCurveModeButton.autoresizingMask = { afFlexibleMinX, afFlexibleMinY }
    leftPaneView.addSubview(toggleCurveModeButton)
    toggleCurveModeButton.onAction do():
        v.curveEditingMode = not v.curveEditingMode

    v.curveEditView = AnimationCurvesEditView.new(newRect(0, 0, 100, 100))
    v.curveEditView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.dopesheetView = DopesheetView.new(newRect(0, 0, 100, 100))
    v.dopesheetView.backgroundColor = newColor(1, 0, 0)
    v.dopesheetView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }

    v.mCurveEditingMode = true
    v.curveEditingMode = false
