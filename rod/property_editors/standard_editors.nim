import strutils

import nimx.view
import nimx.text_field
import nimx.matrixes
import nimx.image
import nimx.button

import rod.property_editors.propedit_registry
import rod.numeric_text_field
import rod.node
import rod.viewport

when defined(js):
    import dom
else:
    import native_dialogs

template toStr(v: SomeReal): string = formatFloat(v, ffDecimal, 2)
template toStr(v: SomeInteger): string = $v

template fromStr(v: string, t: var SomeReal) = t = v.parseFloat()
template fromStr(v: string, t: var SomeInteger) = t = v.parseInt()

proc newScalarPropertyView[T](setter: proc(s: T), getter: proc(): T): View =
    let tf = newNumericTextField(newRect(0, 0, 300, 20))
    tf.text = toStr(getter())
    tf.onAction do():
        var v: T
        fromStr(tf.text, v)
        setter(v)
    result = tf

proc newTextPropertyView(setter: proc(s: string), getter: proc(): string): View =
    let textField = newTextField(newRect(0, 0, 200, 17))
    textField.text = getter()
    textField.onAction do():
        setter(textField.text)
    result = textField

proc newVecPropertyView[T](setter: proc(s: T), getter: proc(): T): View =
    result = View.new(newRect(0, 0, 130, 17))
    const vecLen = high(T) + 1

    var x = 0.Coord
    let width = (result.bounds.width - x) / vecLen

    let pv = result
    proc complexSetter() =
        var val : TVector[vecLen, Coord]
        for i in 0 ..< pv.subviews.len:
            val[i] = TextField(pv.subviews[i]).text.parseFloat()
        setter(val)

    let val = getter()
    for i in 0 ..< vecLen:
        let textField = newNumericTextField(newRect(x, 0, width, result.bounds.height))
        x += width
        if i == vecLen - 1:
            textField.autoresizingMask = {afFlexibleMaxX, afFlexibleMaxY}
        else:
            textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        textField.text = formatFloat(val[i], ffDecimal, 2)
        textField.onAction complexSetter
        result.addSubview(textField)

proc newColorPropertyView(setter: proc(s: Color), getter: proc(): Color): View =
    result = View.new(newRect(0, 0, 130, 17))
    const vecLen = 3 + 1

    let colorView = View.new(newRect(0, 0, 17, 17))
    colorView.backgroundColor = getter()
    result.addSubview(colorView)

    var x = 18.Coord
    let width = (result.bounds.width - x) / vecLen

    let pv = result
    proc complexSetter() =
        let c = newColor(
            TextField(pv.subviews[1]).text.parseFloat(),
            TextField(pv.subviews[2]).text.parseFloat(),
            TextField(pv.subviews[3]).text.parseFloat(),
            TextField(pv.subviews[4]).text.parseFloat(),
            )
        setter(c)
        colorView.backgroundColor = c

    template toVector(c: Color): Vector4 = newVector4(c.r, c.g, c.b, c.a)

    for i in 0 ..< vecLen:
        let textField = newNumericTextField(newRect(x, 0, width, result.bounds.height))
        x += width
        if i == vecLen - 1:
            textField.autoresizingMask = {afFlexibleMaxX, afFlexibleMaxY}
        else:
            textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        textField.text = formatFloat(getter().toVector[i], ffDecimal, 2)
        textField.onAction complexSetter
        result.addSubview(textField)

proc newSizePropertyView(setter: proc(s: Size), getter: proc(): Size): View =
    newVecPropertyView(
        proc(v: Vector2) = setter(newSize(v.x, v.y)),
        proc(): Vector2 =
            let s = getter()
            result = newVector2(s.width, s.height)
            )

proc newPointPropertyView(setter: proc(s: Point), getter: proc(): Point): View =
    newVecPropertyView(
        proc(v: Vector2) = setter(newPoint(v.x, v.y)),
        proc(): Vector2 =
            let s = getter()
            result = newVector2(s.x, s.y)
            )

proc newImagePropertyView(setter: proc(s: Image), getter: proc(): Image): View =
    let b = Button.new(newRect(0, 0, 200, 17))
    b.title = "Open image..."
    b.onAction do():
        when defined(js):
            alert("Files can be opened only in native editor version")
        else:
            let path = callDialogFileOpen("Select Image")
            if not path.isNil:
                setter(imageWithContentsOfFile(path))
    result = b

proc newNodePropertyView(editedNode: Node, setter: proc(s: Node), getter: proc(): Node): View =
    let textField = newTextField(newRect(0, 0, 200, 17))
    let n = getter()
    if n.isNil or n.name.isNil:
        textField.text = "nil"
    else:
        textField.text = n.name
    textField.onAction do():
        setter(editedNode.sceneView.rootNode.findNode(textField.text))
    result = textField


registerPropertyEditor(newTextPropertyView)
registerPropertyEditor(newScalarPropertyView[Coord])
registerPropertyEditor(newScalarPropertyView[float])
registerPropertyEditor(newScalarPropertyView[int])
registerPropertyEditor(newVecPropertyView[Vector2])
registerPropertyEditor(newVecPropertyView[Vector3])
registerPropertyEditor(newVecPropertyView[Vector4])
registerPropertyEditor(newColorPropertyView)
registerPropertyEditor(newSizePropertyView)
registerPropertyEditor(newPointPropertyView)
registerPropertyEditor(newImagePropertyView)
registerPropertyEditor(newNodePropertyView)
