import sequtils, intsets, tables, logging
import nimx / [view, table_view, scroll_view,
    button, text_field, popup_button, window,
    linear_layout, menu, event, property_visitor,
    timer
    ]
import rod/[node, edit_view]
import rod/animation/[property_animation, animation_sampler]

import animation_chart_view, animation_curves_edit_view, dopesheet_view
import animation_editor_types
import variant, json, algorithm

const leftPaneWidth = 200

type
    AnimationEditView* = ref object of EditorTabView
        curveEditView: AnimationCurvesEditView
        dopesheetView: DopesheetView
        propertyTableView: TableView
        # editedProperties: seq[EditedProperty]
        mCurveEditingMode: bool
        mEditedNode: Node
        animationSelector*: PopupButton
        selectedProperties: seq[int]
        cachedAnimation: PropertyAnimation
        # mEditedAnimation*: PropertyAnimation

proc editedAnimation(v: AnimationEditView): EditedAnimation =
    var currComp = v.editor.currentComposition
    if not currComp.isNil:
        result = currComp.currentAnimation

proc `editedAnimation=`(v: AnimationEditView, val: EditedAnimation)=
    v.dopesheetView.editedAnimation = val

proc `editedNode=`*(v: AnimationEditView, n: Node) =
    v.mEditedNode = n

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

proc rebuildAnimation(v: AnimationEditView) =
    v.cachedAnimation = nil
    if v.editedAnimation.isNil: return
    var janim = %v.editedAnimation
    var comp = v.editor.currentComposition
    if comp.isNil: return
    try:
        v.cachedAnimation = newPropertyAnimation(comp.rootNode, janim)
    except:
        v.cachedAnimation = nil
        echo janim
        echo getStackTrace(getCurrentException())
        echo getCurrentExceptionMsg()

proc playEditedAnimation(v: AnimationEditView) =
    v.rebuildAnimation()
    if not v.cachedAnimation.isNil:
        v.window.addAnimation(v.cachedAnimation)

proc reload(v: AnimationEditView) = 
    v.propertyTableView.reloadData()
    v.rebuildAnimation()
    # v.updateDopesheetCurves()

proc onCursorPosChange(v: AnimationEditView, pos: float) =
    if v.cachedAnimation.isNil:
        v.rebuildAnimation()
    
    echo "v.cachedAnimation.isNil ", v.cachedAnimation.isNil
    if not v.cachedAnimation.isNil:
        try:
            v.cachedAnimation.onProgress(pos)
        except: 
            echo getStackTrace(getCurrentException())
            echo getCurrentExceptionMsg()


const topPanelHeight = 25
const bottomPanelHeight = 25

proc createPlayButton(v: AnimationEditView): Button =
    result = Button.new(newRect(0, 0, 50, topPanelHeight))
    result.title = "Play"
    var currentlyPlayingAnimation: Animation
    let b = result
    result.onAction do():
        v.playEditedAnimation()
        # if not currentlyPlayingAnimation.isNil:
        #     currentlyPlayingAnimation.cancel()
        #     currentlyPlayingAnimation = nil
        #     b.title = "Play"
        # elif v.animationSelector.selectedIndex >= 0 and not v.mEditedNode.isNil:
        #     let a = v.mEditedNode.animationNamed(v.animationSelector.selectedItem, true)
        #     if not a.isNil:
        #         currentlyPlayingAnimation = a
        #         a.onComplete do():
        #             b.title = "Play"
        #             currentlyPlayingAnimation = nil
        #         v.window.addAnimation(a)
        #         b.title = "Stop"

proc onRemoveProperty(v: AnimationEditView, pi: int) =
    echo "onRemoveProperty ", pi
    let curAnim = v.editedAnimation
    if not curAnim.isNil:
        curAnim.properties.del(pi)
    v.rebuildAnimation()

proc onSetEnabledProperty(v: AnimationEditView, pi: int, val: bool) =
    echo "onSetEnabledProperty ", pi, " val ", val
    let curAnim = v.editedAnimation
    if not curAnim.isNil and pi < curAnim.properties.len:
        curAnim.properties[pi].enabled = val
    v.rebuildAnimation()

proc onRemoveKeys(v: AnimationEditView, keys: seq[DopesheetSelectedKey])=
    var keys = keys
    # echo "k ", keys
    keys.sort() do(a,b: DopesheetSelectedKey) -> int:
        result = cmp(a.pi, b.pi)
        if result == 0:
            result = cmp(b.ki, a.ki) #del from the end of seq
    
    for k in keys:
        if k.pi < v.editedAnimation.properties.len:
            v.editedAnimation.properties[k.pi].keys.del(k.ki)

    v.rebuildAnimation()

method init*(v: AnimationEditView, r: Rect) =
    procCall v.View.init(r)
    # v.editedProperties = @[]

    let mainSplitView = newHorizontalLayout(v.bounds)
    mainSplitView.userResizeable = true
    mainSplitView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    

    let leftPaneView = View.new(newRect(0, 0, leftPaneWidth, v.bounds.height))
    let playButton = v.createPlayButton()
    leftPaneView.addSubview(playButton)
    leftPaneView.autoresizingMask = { afFlexibleMaxX, afFlexibleHeight }

    v.animationSelector = PopupButton.new(newRect(52, 0, leftPaneView.bounds.width - 52, topPanelHeight))
    v.animationSelector.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
    leftPaneView.addSubview(v.animationSelector)
    # v.animationSelector.onAction do():
    #     if v.animationSelector.selectedIndex >= 0:
    #         let a = v.mEditedNode.animationNamed(v.animationSelector.selectedItem, true)
    #         if a of PropertyAnimation:
    #             v.editedAnimation = PropertyAnimation(a)
    #         else:
    #             v.editedAnimation = nil
    #     else:
    #         v.editedAnimation = nil

    v.propertyTableView = TableView.new(newRect(0, topPanelHeight, leftPaneWidth, leftPaneView.bounds.height - topPanelHeight - bottomPanelHeight))
    # v.propertyTableView.selectionMode = smMultipleSelection
    v.propertyTableView.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}
    let s = newScrollView(v.propertyTableView)
    leftPaneView.addSubview(s)
    mainSplitView.addSubview(leftPaneView)

    v.propertyTableView.numberOfRows = proc(): int =
        if v.editedAnimation.isNil: 0 else: v.editedAnimation.properties.len
    v.propertyTableView.numberOfColumns = 3
        # 0
        # v.editedProperties.len

    v.propertyTableView.createCell = proc (col: int): TableViewCell =
        if col == 0:
            result = newTableViewCell(newCheckbox(newRect(0, 0, 20, 20)))
        elif col == 1:

            result = newTableViewCell(newButton(newRect(0, 0, 20, 20)))
        else:
            result = newTableViewCell(newLabel(newRect(0, 0, 200, 20)))
    v.propertyTableView.configureCell = proc (c: TableViewCell) =
        case c.col:
        of 0:
            let en = Button(c.subviews[0])
            en.onAction do():
                # progress.indeterminate = en.boolValue
                v.onSetEnabledProperty(c.row, en.boolValue)
            
            let curAnim = v.editedAnimation
            if not curAnim.isNil and c.row < curAnim.properties.len:
                en.value = curAnim.properties[c.row].enabled.int8
            
            # en.value = true.int8
        of 1:
            let rem = Button(c.subviews[0])
            rem.title = "D"
            rem.onAction do():
                v.onRemoveProperty(c.row)
        of 2:
            TextField(c.subviews[0]).text = v.editedAnimation.properties[c.row].name
        else: discard

    v.propertyTableView.onSelectionChange = proc() =
        v.selectedProperties = toSeq(items(v.propertyTableView.selectedRows))

    v.propertyTableView.defaultRowHeight = 20

    # let toggleCurveModeButton = Button.new(newRect(leftPaneView.bounds.maxX - 25, leftPaneView.bounds.maxY - bottomPanelHeight, 25, bottomPanelHeight))
    # toggleCurveModeButton.title = "o"
    # toggleCurveModeButton.autoresizingMask = { afFlexibleMinX, afFlexibleMinY }
    # leftPaneView.addSubview(toggleCurveModeButton)
    # toggleCurveModeButton.onAction do():
    #     v.curveEditingMode = not v.curveEditingMode

    # v.curveEditView = AnimationCurvesEditView.new(newRect(0, 0, 100, 100))
    # v.curveEditView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    # v.curveEditView.onCursorPosChange = proc() =
    #     v.onCursorPosChange(v.curveEditView.cursorPos)

    v.dopesheetView = DopesheetView.new(newRect(leftPaneWidth, 0, mainSplitView.bounds.width - leftPaneWidth, mainSplitView.bounds.height))
    v.dopesheetView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.dopesheetView.onCursorPosChange = proc() =
        v.onCursorPosChange(v.dopesheetView.cursorPos)
    # v.dopesheetView.onKeysChanged = proc(pi, ki: int) =
    #     if pi != -1 and ki != -1:
    #         let p = 
    #         v.onRemoveKey(pi, ki)
    # let toView = v.currentLeftPaneView
    # toView.setFrame(newRect(leftPaneWidth, 0, mainSplitView.bounds.width - leftPaneWidth, mainSplitView.bounds.height))
    mainSplitView.addSubview(v.dopesheetView)
    v.addSubview(mainSplitView)

method viewWillMoveToWindow*(v: AnimationEditView, w: Window) =
    echo "AnimationEditView ", v.editor.isNil
    if w.isNil:
        v.editor.onEditModeChanged(emScene)
    else:
        setTimeout(0.1) do(): # hack to prevent sigfault on editor start
            v.editor.onEditModeChanged(emAnimation)

method acceptsFirstResponder*(v: AnimationEditView): bool = true

proc insertKeyframeAtCurPos(v: AnimationEditView) =
    let cursorPos = v.currentLeftPaneView.cursorPos
    echo "cursorPos ", cursorPos
    let curAnim = v.editedAnimation
    if curAnim.isNil: return

    for i in v.selectedProperties:
        if i >= curAnim.properties.len: continue
        let p = curAnim.properties[i]
        p.addKeyAtPosition(cursorPos)

    v.rebuildAnimation()
    # for ep in v.editedProperties:
#         echo "addKey ", ep.name, " cp ", cursorPos
#         ep.curve.addKeyAtPosWithValueFromGetter(cursorPos, ep.sng)
#     v.setNeedsDisplay()

method onKeyDown*(v: AnimationEditView, e: var Event): bool =
    if e.keyCode == VirtualKey.K:
        v.insertKeyframeAtCurPos()
        result = true
    elif e.keyCode == VirtualKey.Delete:
        v.onRemoveKeys(v.dopesheetView.selectedKeys)
        v.dopesheetView.clearSelection()
        result = true
    v.setNeedsDisplay()

method tabSize*(v: AnimationEditView, bounds: Rect): Size=
    result = newSize(bounds.width, 450.0)

method tabAnchor*(v: AnimationEditView): EditorTabAnchor =
    result = etaBottom

method setEditedNode*(v: AnimationEditView, n: Node)=
    v.editedNode = n

method onCompositionChanged*(v: AnimationEditView, comp: CompositionDocument) =
    procCall v.EditorTabView.onCompositionChanged(comp)
    v.editedNode = comp.rootNode
    echo "onCompositionChanged "
    v.reload()

proc addEditedProperty*(v: AnimationEditView, node: Node, prop: string, sng: Variant) = 
    var currComp = v.editor.currentComposition

    if currComp.currentAnimation.isNil:
        echo "currentAnimation nil "
        currComp.currentAnimation = new(EditedAnimation)
        v.editedAnimation = currComp.currentAnimation

    var ep = newEditedProperty(node, prop, sng)
    block reuseProperty:
        for p in currComp.currentAnimation.properties:
            if ep.name == p.name:
                ep = p
                break reuseProperty

        template createCurve(T: typedesc) =
            discard newAnimationCurve[T]()
        template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
        try: #incompatible type for animation should throw exception
            switchAnimatableTypeId(ep.sng.typeId, getSetterAndGetterTypeId, createCurve)
            currComp.currentAnimation.properties.add(ep)
        except:
            echo "Can't add edited property"
            echo getCurrentExceptionMsg()

    # ep.sng = sng

    v.reload()
#[
    composition
]#

registerEditorTab("Animation", AnimationEditView)
