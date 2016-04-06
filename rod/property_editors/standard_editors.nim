import strutils

import nimx.view
import nimx.text_field
import nimx.matrixes
import nimx.image
import nimx.button
import nimx.color_picker

import rod.property_editors.propedit_registry
import rod.numeric_text_field
import rod.node
import rod.viewport

when defined(js):
    from dom import alert
elif not defined(android) and not defined(ios):
    import native_dialogs

var gColorPicker*: ColorPickerView

template toStr(v: SomeReal, precision: uint): string = formatFloat(v, ffDecimal, precision)
template toStr(v: SomeInteger): string = $v

template fromStr(v: string, t: var SomeReal) = t = v.parseFloat()
template fromStr(v: string, t: var SomeInteger) = t = v.parseInt()

proc newScalarPropertyView[T](setter: proc(s: T), getter: proc(): T): View =
    let tf = newNumericTextField(newRect(0, 0, 300, 24))
    tf.textColor = newGrayColor(0.0)
    when T is SomeReal:
        tf.text = toStr(getter(), tf.precision)
    else:
        tf.text = toStr(getter())
    tf.onAction do():
        var v: T
        try:
            fromStr(tf.text, v)
            setter(v)
        except ValueError:
            discard
    result = tf

proc newTextPropertyView(setter: proc(s: string), getter: proc(): string): View =
    let textField = newTextField(newRect(0, 0, 200, 24))
    textField.text = getter()
    textField.textColor = newGrayColor(0.0)
    textField.onAction do():
        setter(textField.text)
    result = textField

proc newVecPropertyView[T](setter: proc(s: T), getter: proc(): T): View =
    result = View.new(newRect(0, 0, 208, 24))
    const vecLen = high(T) + 1

    var x = 0.Coord
    let width = (result.bounds.width - x) / vecLen - vecLen

    let pv = result
    proc complexSetter() =
        var val : TVector[vecLen, Coord]
        for i in 0 ..< pv.subviews.len:
            try:
                val[i] = TextField(pv.subviews[i]).text.parseFloat()
            except ValueError:
                return
        setter(val)

    let val = getter()
    for i in 0 ..< vecLen:
        let textField = newNumericTextField(newRect(x, 0, width, result.bounds.height))
        x += width + 6
        if i == vecLen - 1:
            textField.autoresizingMask = {afFlexibleMaxX, afFlexibleMaxY}
        else:
            textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        textField.text = toStr(val[i], textField.precision)
        textField.textColor = newGrayColor(0.0)
        textField.onAction complexSetter
        result.addSubview(textField)

proc newColorPropertyView(setter: proc(s: Color), getter: proc(): Color): View =
    result = View.new(newRect(0, 0, 140, 24))
    const vecLen = 3 + 1

    let colorView = View.new(newRect(0, 0, 24, 24))
    colorView.backgroundColor = getter()
    result.addSubview(colorView)

    var x = 18.Coord
    let width = (result.bounds.width - x) / vecLen

    var prevColor: Color

    let pv = result
    proc complexSetter() =
        try:
            let c = newColor(
                TextField(pv.subviews[1]).text.parseFloat(),
                TextField(pv.subviews[2]).text.parseFloat(),
                TextField(pv.subviews[3]).text.parseFloat(),
                TextField(pv.subviews[4]).text.parseFloat(),
                )
            setter(c)
            colorView.backgroundColor = c

            prevColor = c

            if not gColorPicker.isNil:
                gColorPicker.colorHasChanged(rgbToHSV(c.r, c.g, c.b))
                gColorPicker.removeFromSuperview()
                gColorPicker = nil

            if gColorPicker.isNil:
                gColorPicker = newColorPickerView(newRect(0, 0, 300, 200))
                gColorPicker.setFrameOrigin(newPoint(pv.frame.x+140+300, 0))

                let pickerCloseButton = Button.new(newRect(0, 0, 25, 25))
                pickerCloseButton.title = "x"
                pickerCloseButton.onAction do():
                    gColorPicker.removeFromSuperview()
                    gColorPicker = nil
                let pickerCancelButton = Button.new(newRect(0, 25, 25, 25))
                pickerCancelButton.title = "c"
                pickerCancelButton.onAction do():
                    TextField(pv.subviews[1]).text = $prevColor.r
                    TextField(pv.subviews[2]).text = $prevColor.g
                    TextField(pv.subviews[3]).text = $prevColor.b
                    TextField(pv.subviews[4]).text = $prevColor.a

                    setter(prevColor)
                    colorView.backgroundColor = prevColor
                    gColorPicker.colorHasChanged(rgbToHSV(prevColor.r, prevColor.g, prevColor.b))

                gColorPicker.addSubview(pickerCloseButton)
                gColorPicker.addSubview(pickerCancelButton)
                pv.window.addSubview(gColorPicker)

                gColorPicker.colorHasChanged(rgbToHSV(c.r, c.g, c.b))
                gColorPicker.onColorSelected = proc(pc: Color) =
                    TextField(pv.subviews[1]).text = $pc.r
                    TextField(pv.subviews[2]).text = $pc.g
                    TextField(pv.subviews[3]).text = $pc.b
                    TextField(pv.subviews[4]).text = $pc.a

                    setter(pc)
                    colorView.backgroundColor = pc
        except ValueError:
            discard

    template toVector(c: Color): Vector4 = newVector4(c.r, c.g, c.b, c.a)

    for i in 0 ..< vecLen:
        let textField = newNumericTextField(newRect(x, 0, width, result.bounds.height))
        x += width
        if i == vecLen - 1:
            textField.autoresizingMask = {afFlexibleMaxX, afFlexibleMaxY}
        else:
            textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        textField.text = toStr(getter().toVector[i], textField.precision)
        textField.textColor = newGrayColor(0.0)
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

when not defined(android) and not defined(ios):
    proc newImagePropertyView(setter: proc(s: Image), getter: proc(): Image): View =
        let b = Button.new(newRect(0, 0, 200, 24))
        b.title = "Open image..."
        b.onAction do():
            when defined(js):
                alert("Files can be opened only in native editor version")
            else:
                let path = callDialogFileOpen("Select Image")
                if not path.isNil:
                    setter(imageWithContentsOfFile(path))
        result = b

    registerPropertyEditor(newImagePropertyView)

proc newNodePropertyView(editedNode: Node, setter: proc(s: Node), getter: proc(): Node): View =
    let textField = newTextField(newRect(0, 0, 200, 24))
    let n = getter()
    textField.textColor = newGrayColor(0.0)
    if n.isNil or n.name.isNil:
        textField.text = "nil"
    else:
        textField.text = n.name
    textField.onAction do():
        setter(editedNode.sceneView.rootNode.findNode(textField.text))
    result = textField

proc newBoolPropertyView(editedNode: Node, setter: proc(s: bool), getter: proc(): bool): View =
    let cb = newCheckbox(newRect(0, 0, 200, 24))
    cb.value = if getter(): 1 else: 0
    cb.onAction do():
        setter(cb.boolValue)
    result = cb

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
registerPropertyEditor(newNodePropertyView)
registerPropertyEditor(newBoolPropertyView)
