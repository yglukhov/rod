import nimx/[view, text_field, button, 
    scroll_view, linear_layout, property_visitor,
    expanding_view, stack_view, slider, popup_button,
    editor/bezier_view, pasteboard/pasteboard
]

import rod/property_editors/[propedit_registry, standard_editors]
import rod/animation/[property_animation]
import rod / editor / [ animation/animation_editor_types, editor_types ]
import algorithm, tables, variant, sequtils, strutils, json

export view


const componentsViewSize = newSize(200, 300)

type AnimatioKeyInspectorView* = ref object of View
    propView: LinearLayout
    scView: ScrollView
    autoUpdate: bool
    onKeyChanged*: proc(k: EditedKey)

method init*(i: AnimatioKeyInspectorView, r: Rect) =
    procCall i.View.init(r)
    i.resizingMask = "wh"

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

proc buildInspector(i: AnimatioKeyInspectorView, k: EditedKey): View =
    var expView = newExpandingView(newRect(0, 20, 328, 20.0))
    expView.title = k.property.name & " : " & k.position.formatFloat(ffDecimal, 2)
    proc changeInspectorView() =
        # echo "key changed for ", k.property.name
        if not i.onKeyChanged.isNil:
            i.onKeyChanged(k)
    
    var visitor : PropertyVisitor
    visitor.requireName = true
    visitor.requireSetter = true
    visitor.requireGetter = true
    visitor.flags = { pfAnimatable, pfEditable }
    visitor.commit = proc() =
        let propView = propertyEditorForProperty(newVariant(), visitor.name, visitor.setterAndGetter, nil, changeInspectorView)
        propView.autoresizingMask = {afFlexibleWidth}
        let propHolder = newView(propView.frame)
        propHolder.addSubview(propView)
        expView.addContent(propHolder)

    visitor.visitProperty("position", k.position)

    block keyValueInspector:
        var vsng: Variant
        template getKeyValue(T: typedesc) =
            var sng: SetterAndGetter[T]
            sng.setter = proc(val: T) = 
                k.value = newVariant(val)
                if not k.property.isNil: # change value at proprty
                    k.property.sng.get(SetterAndGetter[T]).setter(val)
                changeInspectorView()
            sng.getter = proc(): T = k.value.get(T)
            vsng = newVariant(sng)
        switchAnimatableTypeId(k.value.typeId, getTypeId, getKeyValue)

        let propView = propertyEditorForProperty(newVariant(), "value", vsng, nil, nil)
        propView.autoresizingMask = {afFlexibleWidth}
        let propHolder = newView(propView.frame)
        propHolder.addSubview(propView)
        expView.addContent(propHolder)

    visitor.visitProperty("interpolation", k.interpolation)

    expView.expand()
    result = expView

proc `inspectedKeys=`*(v: AnimatioKeyInspectorView, keys: seq[EditedKey]) =
    let scrollBar = v.scView.verticalScrollBar()
    let oldPos = scrollBar.value()

    while v.propView.subviews.len() > 0:
        v.propView.subviews[0].removeFromSuperview()

    # echo "inspectedKeys ", keys.len
    if keys.len == 0: return
    var keys = keys
    keys.sort() do(a, b: EditedKey) -> int:
        result = cmp(a.property.name, b.property.name)
        if result == 0:
            result = cmp(a.position, b.position)
    
    for k in keys:
        v.propView.addSubview(v.buildInspector(k))

    scrollBar.value = oldPos
    scrollBar.sendAction()


proc newInterpolationPropertyView(setter: proc(s: EInterpolation), getter: proc(): EInterpolation): PropertyEditorView =
    var r = PropertyEditorView.new(newRect(0, 0, 250, editorRowHeight + 270))
    var bezierPoints:array[4, float]
    
    var inter = getter()

    var curveEdit = View.new(newRect(0, editorRowHeight, 230, 250))
    curveEdit.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    
    var bezierView = BezierView.new(newRect(0, 20, 230, 230))
    bezierView.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    curveEdit.addSubview(bezierView)

    proc setCurve(arr: array[4, float]) =
        bezierPoints = arr
        bezierView.p1 = bezierPoints[0]
        bezierView.p2 = bezierPoints[1]
        bezierView.p3 = bezierPoints[2]
        bezierView.p4 = bezierPoints[3]
        bezierView.setNeedsDisplay()

    setCurve([0.5, 0.5, 0.5, 0.5])

    var resetButton = newButton(newRect(0, 0, 40, editorRowHeight))
    resetButton.title = "reset"
    resetButton.autoresizingMask = {afFlexibleMaxY}
    resetButton.onAction do():
        setCurve([0.5, 0.5, 0.5, 0.5])
        if not r.changeInspector.isNil():
            r.changeInspector()
    curveEdit.addSubview(resetButton)

    var copyButton = newButton(newRect(50, 0, 40, editorRowHeight))
    copyButton.title = "copy"
    copyButton.autoresizingMask = {afFlexibleMaxY}
    copyButton.onAction do():
        let pbi = newPasteboardItem(BezierPboardKind, $(%bezierPoints))
        pasteboardWithName(PboardGeneral).write(pbi)
    curveEdit.addSubview(copyButton)

    var pasteButton = newButton(newRect(100, 0, 40, editorRowHeight))
    pasteButton.title = "paste"
    pasteButton.autoresizingMask = {afFlexibleMaxY}
    pasteButton.onAction do():
        let pbi = pasteboardWithName(PboardGeneral).read(BezierPboardKind)
        setCurve(parseJson(pbi.data).to(array[4, float]))
        if not r.changeInspector.isNil():
            r.changeInspector()
    curveEdit.addSubview(pasteButton)

    let items = toSeq(low(KeyInterpolationKind) .. high(KeyInterpolationKind)).map do(v: KeyInterpolationKind) -> string: $v
    var popupButton = PopupButton.new(newRect(0, 0, 200, editorRowHeight))
    popupButton.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    popupButton.items = items
    popupButton.onAction do():
        let i = popupButton.selectedIndex
        if i != -1:
            if items[i] == $KeyInterpolationKind.eiBezier and curveEdit.superview.isNil:
                r.addSubview(curveEdit)

            elif items[i] != $KeyInterpolationKind.eiBezier and not curveEdit.superview.isNil:
                curveEdit.removeFromSuperview()

            var v = EInterpolation(kind: parseEnum[KeyInterpolationKind](items[i]))
            if v.kind == KeyInterpolationKind.eiBezier:
                v.points = bezierPoints
            setter v
            if not r.changeInspector.isNil():
                r.changeInspector()

        # echo "selected interpolation ", popupButton.selectedIndex
    popupButton.selectedIndex = items.find($inter.kind)
    r.addSubview(popupButton)
    
    bezierView.onAction do():
        bezierPoints[0] = bezierView.p1
        bezierPoints[1] = bezierView.p2
        bezierPoints[2] = bezierView.p3
        bezierPoints[3] = bezierView.p4

        setter EInterpolation(kind: KeyInterpolationKind.eiBezier, points: bezierPoints)
        if not r.changeInspector.isNil():
            r.changeInspector()

    if inter.kind == KeyInterpolationKind.eiBezier:
        setCurve(inter.points)

        r.addSubview(curveEdit) 
    result = r


registerPropertyEditor(newInterpolationPropertyView)
