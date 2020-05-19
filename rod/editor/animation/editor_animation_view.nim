import nimx / [view, table_view, scroll_view,
    button, text_field, popup_button, window,
    linear_layout, menu, event, property_visitor,
    timer
    ]
import rod/[node, edit_view]
import rod/animation/[property_animation, animation_sampler]

import animation_chart_view, dopesheet_view
import animation_editor_types, animation_key_inspector
import variant, json, algorithm, parseutils,
    sequtils, intsets, tables, logging

const leftPaneWidth = 200

type
    PropertyControls = enum
        pcEnable
        pcDelete
        pcName
        pcKey

    AnimationEditView* = ref object of EditorTabView
        dopesheetView: DopesheetView
        propertyTableView: TableView
        animationSelector: PopupButton
        selectedProperties: seq[int]

        keysInspector: AnimatioKeyInspectorView
        cachedAnimation: Animation
        nameField: TextField
        fpsField: TextField
        durationField: TextField

proc editedAnimation(v: AnimationEditView): EditedAnimation =
    var currComp = v.editor.currentComposition
    if not currComp.isNil:
        result = currComp.currentAnimation

proc reload(v: AnimationEditView)

proc `editedAnimation=`(v: AnimationEditView, val: EditedAnimation)=
    if val != nil:
        v.dopesheetView.editedAnimation = val
        v.dopesheetView.sampleRate = val.sampleRate()
        v.nameField.text = val.name
        v.fpsField.text = $val.fps
        v.durationField.text = $val.duration
    else:
        v.dopesheetView.editedAnimation = nil
        v.nameField.text = ""
        v.fpsField.text = ""
        v.durationField.text = ""
    
    var currComp = v.editor.currentComposition
    if not currComp.isNil:
        currComp.currentAnimation = val
    v.reload()

proc newEditedAnimation(v: AnimationEditView) =
    var currComp = v.editor.currentComposition
    if not currComp.isNil:
        var a = new(EditedAnimation)
        a.fps = 25
        a.duration = 1.0
        a.name = "myanim"
        currComp.animations.add(a)
        currComp.currentAnimation = a
        v.editedAnimation = a

proc deleteEditedAnimation(v: AnimationEditView)=
    var currComp = v.editor.currentComposition
    if not currComp.isNil:
        let i = currComp.animations.find(currComp.currentAnimation)
        if i != -1:
            currComp.animations.del(i)
        v.editedAnimation = nil

let colors = [
    newColor(1, 0, 0),
    newColor(0, 1, 0),
    newColor(0, 0, 1),
    newColor(0, 1, 1),
    newColor(1, 0, 1)
]

proc rebuildAnimation(v: AnimationEditView) =
    if not v.cachedAnimation.isNil:
        v.cachedAnimation.cancel()
    v.cachedAnimation = nil
    if v.editedAnimation.isNil: return
    var janim = %v.editedAnimation
    var comp = v.editor.currentComposition
    if comp.isNil: return
    try:
        v.cachedAnimation = newPropertyAnimation(comp.rootNode, janim).addOnAnimate() do(p: float):
            v.dopesheetView.cursorPos = p
        echo janim
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
    var currComp = v.editor.currentComposition
    if not currComp.isNil:
        var items: seq[string]
        for a in currComp.animations:
            items.add(a.name)
        v.animationSelector.items = items

    # v.updateDopesheetCurves()

proc onCursorPosChange(v: AnimationEditView, pos: float) =
    if v.cachedAnimation.isNil:
        v.rebuildAnimation()
    
    if not v.cachedAnimation.isNil:
        try:
            v.cachedAnimation.onProgress(pos)
        except: 
            echo getStackTrace(getCurrentException())
            echo getCurrentExceptionMsg()


const topPanelHeight = 25
const bottomPanelHeight = 25

proc onRemoveProperty(v: AnimationEditView, pi: int) =
    echo "onRemoveProperty ", pi
    let curAnim = v.editedAnimation
    if not curAnim.isNil and not curAnim.propertyAtIndex(pi).isNil:
        curAnim.properties.del(pi)
    v.reload()

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

proc createTopPanel(v: AnimationEditView, r: Rect): View =
    result = new(View, r)
    let bh = r.height - 2
    let bw = bh
    
    var w = 1.0
    var toStartButton = newButton(newRect(w, 1, bw, bh))
    toStartButton.title = "B" 
    toStartButton.onAction do():
        if not v.cachedAnimation.isNil:
            v.cachedAnimation.cancel()
            v.cachedAnimation.onProgress(0.0)
    w += bw + 1
    result.addSubview(toStartButton)
    
    var playButton = newButton(newRect(w, 1, bw, bh))
    playButton.title = "P" 
    playButton.onAction do():
        if not v.cachedAnimation.isNil:
            v.cachedAnimation.cancel()
            v.window.addAnimation(v.cachedAnimation)
    w += bw + 1
    result.addSubview(playButton)

    var stopButton = newButton(newRect(w, 1, bw, bh))
    stopButton.title = "S" 
    stopButton.onAction do():
        if not v.cachedAnimation.isNil:
            v.cachedAnimation.cancel()
    w += bw + 1
    result.addSubview(stopButton)
    
    var toEndButton = newButton(newRect(w, 1, bw, bh))
    toEndButton.title = "E" 
    toEndButton.onAction do():
        if not v.cachedAnimation.isNil:
            v.cachedAnimation.cancel()
            v.cachedAnimation.onProgress(1.0)
    w += bw + 20
    result.addSubview(toEndButton)

    var addButton = newButton(newRect(w, 1, bw, bh))
    addButton.title = "A" 
    addButton.onAction do():
        v.newEditedAnimation()
    w += bw + 10
    result.addSubview(addButton)

    var delButton = newButton(newRect(w, 1, bw, bh))
    delButton.title = "D" 
    delButton.onAction do():
        v.deleteEditedAnimation()
    w += bw + 10
    result.addSubview(delButton)

    v.animationSelector = PopupButton.new(newRect(w, 1, r.width - w, bh))
    v.animationSelector.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
    v.animationSelector.onAction do():
        var currComp = v.editor.currentComposition
        let i = v.animationSelector.selectedIndex
        if not currComp.isNil and i >= 0 and i < currComp.animations.len:
            v.editedAnimation = currComp.animations[i]
        else:
            v.editedAnimation = nil

    result.addSubview(v.animationSelector)

proc createBottomPanel(v: AnimationEditView, r: Rect): View =
    result = new(View, r)
    let lh = r.height - 2
    let lw = 100.0
    
    var w = 1.0
    v.nameField = newTextField(newRect(w, 1, lw, lh))
    v.nameField.onAction do():
        if v.editedAnimation.isNil: return
        v.editedAnimation.name = v.nameField.text
    w += lw + 10
    result.addSubview(v.nameField)

    var durLbl = newLabel(newRect(w, 1, lw * 0.5, lh))
    durLbl.text = "dur:"
    result.addSubview(durLbl)

    v.durationField = newTextField(newRect(w + lw * 0.5, 1, lw * 0.5, lh))
    v.durationField.onAction do():
        if v.editedAnimation.isNil: return
        if parseFloat(v.durationField.text, v.editedAnimation.duration) != 0:
            v.dopesheetView.sampleRate = v.editedAnimation.sampleRate()
            v.rebuildAnimation()
    w += lw
    result.addSubview(v.durationField)

    var fpsLbl = newLabel(newRect(w, 1, lw * 0.5, lh))
    fpsLbl.text = "fps:"
    result.addSubview(fpsLbl)
    
    v.fpsField = newTextField(newRect(w + lw * 0.5, 1, lw * 0.5, lh))
    v.fpsField.onAction do():
        if v.editedAnimation.isNil: return
        if parseInt(v.fpsField.text, v.editedAnimation.fps) != 0:
            v.dopesheetView.sampleRate = v.editedAnimation.sampleRate()
            v.rebuildAnimation()
    w += lw
    result.addSubview(v.fpsField)


method init*(v: AnimationEditView, r: Rect) =
    procCall v.View.init(r)

    let mainSplitView = newHorizontalLayout(v.bounds)
    mainSplitView.name = "test"
    mainSplitView.userResizeable = true
    mainSplitView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    mainSplitView.rightMargin = 4.0
    v.addSubview(mainSplitView)

    let leftPaneView = View.new(newRect(0, 0, leftPaneWidth, v.bounds.height))
    leftPaneView.autoresizingMask = { afFlexibleMaxX, afFlexibleHeight }
 

    v.propertyTableView = TableView.new(newRect(0, topPanelHeight, leftPaneWidth, leftPaneView.bounds.height - topPanelHeight - bottomPanelHeight))
    v.propertyTableView.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}    
    v.propertyTableView.numberOfColumns = 4
    let s = newScrollView(v.propertyTableView)
    leftPaneView.addSubview(s)
    
    v.propertyTableView.numberOfRows = proc(): int =
        if v.editedAnimation.isNil: 0 else: v.editedAnimation.properties.len

    v.propertyTableView.createCell = proc (col: int): TableViewCell =
        case col.PropertyControls
        of pcEnable:
            result = newTableViewCell(newCheckbox(newRect(0, 0, 20, 20)))
        of pcName:
            result = newTableViewCell(newLabel(newRect(0, 0, 200, 20)))
        of pcDelete:
            result = newTableViewCell(newButton(newRect(0, 0, 20, 20)))
        of pcKey:
            result = newTableViewCell(newButton(newRect(0, 0, 20, 20)))
    v.propertyTableView.configureCell = proc (c: TableViewCell) =
        case c.col.PropertyControls:
        of pcEnable:
            let en = Button(c.subviews[0])
            en.onAction do():
                v.onSetEnabledProperty(c.row, en.boolValue)
            
            let curAnim = v.editedAnimation
            if not curAnim.isNil and c.row < curAnim.properties.len:
                en.value = curAnim.properties[c.row].enabled.int8
        of pcName:
            TextField(c.subviews[0]).text = v.editedAnimation.properties[c.row].name
        of pcKey:
            let key = Button(c.subviews[0])
            key.title = "K"
            key.onAction do():
                let p = v.editedAnimation.propertyAtIndex(c.row)
                if not p.isNil:
                    let cursorPos = v.dopesheetView.cursorPos
                    p.addKeyAtPosition(cursorPos)
                    v.rebuildAnimation()
        of pcDelete:
            let rem = Button(c.subviews[0])
            rem.title = "D"
            rem.onAction do():
                v.onRemoveProperty(c.row)

    v.propertyTableView.onSelectionChange = proc() =
        v.selectedProperties = toSeq(items(v.propertyTableView.selectedRows))

    v.propertyTableView.defaultRowHeight = 20
    
    var tv = v.createTopPanel(newRect(1, 1, leftPaneWidth, topPanelHeight))
    tv.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    leftPaneView.addSubview(tv)

    var bv = v.createBottomPanel(newRect(1, leftPaneView.bounds.maxY - bottomPanelHeight, leftPaneView.bounds.width, bottomPanelHeight))
    bv.autoresizingMask = {afFlexibleWidth, afFlexibleMinY}
    leftPaneView.addSubview(bv)
    mainSplitView.addSubview(leftPaneView)

    v.dopesheetView = DopesheetView.new(newRect(0, 0, mainSplitView.bounds.width - leftPaneWidth, mainSplitView.bounds.height))
    v.dopesheetView.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.dopesheetView.onCursorPosChange = proc() =
        if not v.cachedAnimation.isNil:
            v.cachedAnimation.cancel()
        v.onCursorPosChange(v.dopesheetView.cursorPos)
    v.dopesheetView.onKeysChanged = proc(arr: seq[DopesheetSelectedKey]) =
        let a = v.editedAnimation
        for k in arr:
            a.propertyAtIndex(k.pi).sortKeys()
        v.rebuildAnimation()
    
    v.dopesheetView.onKeysSelected = proc(arr: seq[DopesheetSelectedKey]) =
        var keys: seq[EditedKey]
        for e in arr:
            let k = v.editedAnimation.keyAtIndex(e.pi, e.ki)
            if k.isNil: continue
            keys.add(k)
        v.keysInspector.inspectedKeys = keys

    mainSplitView.addSubview(v.dopesheetView)
    mainSplitView.setDividerPosition(350.0, 0)

    v.keysInspector = AnimatioKeyInspectorView.new(newRect(0, 0, 100, 100))
    v.keysInspector.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }
    v.keysInspector.onKeyChanged = proc(k: EditedKey) =
        v.rebuildAnimation()
    mainSplitView.addSubview(v.keysInspector)



method viewWillMoveToWindow*(v: AnimationEditView, w: Window) =
    procCall v.View.viewWillMoveToWindow(w)
    # echo "AnimationEditView ", v.editor.isNil
    if w.isNil:
        v.editor.onEditModeChanged(emScene)
    else:
        setTimeout(0.1) do(): # hack to prevent sigfault on editor start
            v.editor.onEditModeChanged(emAnimation)
            v.editedAnimation = v.editedAnimation

method acceptsFirstResponder*(v: AnimationEditView): bool = true

proc insertKeyframeAtCurPos(v: AnimationEditView) =
    let cursorPos = v.dopesheetView.cursorPos
    # echo "cursorPos ", cursorPos
    let curAnim = v.editedAnimation
    if curAnim.isNil: return

    for i in v.selectedProperties:
        if i >= curAnim.properties.len: continue
        let p = curAnim.properties[i]
        p.addKeyAtPosition(cursorPos)

    v.rebuildAnimation()

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

method onCompositionChanged*(v: AnimationEditView, comp: CompositionDocument) =
    procCall v.EditorTabView.onCompositionChanged(comp)
    if comp.animations.len > 0:
        v.editedAnimation = comp.animations[0]
    else:
        v.editedAnimation = nil
    
    v.reload()

proc addEditedProperty*(v: AnimationEditView, node: Node, prop: string, sng: Variant) = 
    var currComp = v.editor.currentComposition

    if currComp.currentAnimation.isNil:
        v.newEditedAnimation()

    var ep = newEditedProperty(node, prop, sng)
    block reuseProperty:
        for p in currComp.currentAnimation.properties:
            if ep.name == p.name:
                ep = p
                break reuseProperty

        
        try: #incompatible type for animation should throw exception
            template createCurve(T: typedesc) =
                discard
            template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
            switchAnimatableTypeId(ep.sng.typeId, getSetterAndGetterTypeId, createCurve)

            currComp.currentAnimation.properties.add(ep)
        except:
            echo "Can't add edited property"
            echo getCurrentExceptionMsg()

    v.reload()


registerEditorTab("Animation", AnimationEditView)
