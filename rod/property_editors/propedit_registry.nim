import tables
import nimx.view
import nimx.text_field
import nimx.font

import rod.node
import rod.property_visitor
import variant
import rod.meta_data

type PropertyEditorView* = ref object of View
    onChange*: proc()
    changeInspector*: proc()

var propEditors = initTable[TypeId, proc(n: Node, v: Variant): PropertyEditorView]()

proc registerPropertyEditor*[T](createView: proc(n: Node, setter: proc(s: T), getter: proc(): T): PropertyEditorView) =
    propEditors[getTypeId(SetterAndGetter[T])] = proc(n: Node, v: Variant): PropertyEditorView =
        let sng = v.get(SetterAndGetter[T])
        result = createView(n, sng.setter, sng.getter)

proc registerPropertyEditor*[T](createView: proc(setter: proc(s: T), getter: proc(): T): PropertyEditorView) =
    propEditors[getTypeId(SetterAndGetter[T])] = proc(n: Node, v: Variant): PropertyEditorView =
        let sng = v.get(SetterAndGetter[T])
        result = createView(sng.setter, sng.getter)

var gEditorFont: Font

proc editorFont*(): Font =
    if gEditorFont.isNil: gEditorFont = systemFontOfSize(14)
    result = gEditorFont

const editorRowHeight* = 16

proc propertyEditorForProperty*(n: Node, title: string, v: Variant, onChangeCallback, changeInspectorCallback: proc()): View =
    let creator = propEditors.getOrDefault(v.typeId)
    result = View.new(newRect(0, 0, 328, editorRowHeight))
    result.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    let label = newLabel(newRect(0, 0, 100, editorRowHeight))
    label.textColor = newGrayColor(0.9)
    label.text = title & ":"
    label.font = editorFont()
    result.addSubview(label)
    if creator.isNil:
        label.text = title & " - Unknown property"
    else:
        let editor = creator(n, v)
        editor.setFrameOrigin(newPoint(label.frame.width, 0))
        var sz = newSize(result.bounds.width - label.frame.width, editor.frame.height)
        editor.setFrameSize(sz)
        editor.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        result.addSubview(editor)

        sz = result.frame.size
        sz.height = editor.frame.height
        result.setFrameSize(sz)

        editor.onChange = onChangeCallback
        editor.changeInspector = changeInspectorCallback
