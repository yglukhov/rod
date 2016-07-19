import nimx.view
import nimx.property_editors.propedit_registry as npr

export npr

import rod.node
import variant
<<<<<<< HEAD
import tables
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

proc propertyEditorForProperty*(n: Node, title: string, v: Variant, onChangeCallback, changeInspectorCallback: proc()): View =
    let creator = propEditors.getOrDefault(v.typeId)
    result = View.new(newRect(6, 6, 328, 36))
    let label = newLabel(newRect(6, 6, 100, 36))
    label.textColor = newGrayColor(0.9)
    label.text = title & ":"
    result.addSubview(label)
    if creator.isNil:
        label.text = title & " - Unknown property"

proc propertyEditorForProperty*(n: Node, title: string, v: Variant, onChangeCallback, changeInspectorCallback: proc()): View =
    propertyEditorForProperty(newVariant(n), title, v, onChangeCallback, changeInspectorCallback)
