import nimx.view
import nimx.text_field

import rod.property_visitor
import variant
import tables

var propEditors = initTable[TypeId, proc(v: Variant): View]()

proc registerPropertyEditor*[T](createView: proc(setter: proc(s: T), getter: proc(): T): View) =
    propEditors[getTypeId(SetterAndGetter[T])] = proc(v: Variant): View =
        let sng = v.get(SetterAndGetter[T])
        result = createView(sng.setter, sng.getter)

proc propertyEditorForProperty*(title: string, v: Variant): View =
    let creator = propEditors.getOrDefault(v.typeId)
    result = View.new(newRect(0, 0, 200, 20))
    let label = newLabel(newRect(0, 0, 70, 20))
    label.text = title & ":"
    result.addSubview(label)
    if creator.isNil:
        label.text = title & " - Unknown property"
    else:
        let editor = creator(v)
        var sz = result.frame.size
        sz.height = editor.frame.height
        editor.setFrameOrigin(newPoint(label.frame.width, 0))
        editor.setFrameSize(sz)
        sz = newSize(result.bounds.width - label.frame.width, editor.frame.height)
        editor.setFrameSize(sz)
        editor.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        result.addSubview(editor)
