import strutils
import tables
import algorithm

import nimx.view
import nimx.text_field
import nimx.matrixes
import nimx.image
import nimx.button
import nimx.color_picker
import nimx.context
import nimx.portable_gl
import nimx.popup_button
import nimx.font
import nimx.linear_layout

import rod.property_editors.propedit_registry
import rod.numeric_text_field
import rod.node
import rod.viewport
import rod.quaternion
import rod.component.mesh_component
import rod.property_visitor

when defined(js):
    from dom import alert
elif not defined(android) and not defined(ios) and not defined(emscripten):
    import native_dialogs

var gColorPicker*: ColorPickerView
var currEditedNode: Node

template toStr(v: SomeReal, precision: uint): string = formatFloat(v, ffDecimal, precision)
template toStr(v: SomeInteger): string = $v

template fromStr(v: string, t: var SomeReal) = t = v.parseFloat()
template fromStr(v: string, t: var SomeInteger) = t = v.parseInt()

proc newScalarPropertyView[T](setter: proc(s: T), getter: proc(): T): PropertyEditorView =
    result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    let tf = newNumericTextField(newRect(0, 0, 208, editorRowHeight))
    tf.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    tf.font = editorFont()
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
    result.addSubview(tf)

proc newTextPropertyView(setter: proc(s: string), getter: proc(): string): PropertyEditorView =
    result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    let textField = newTextField(newRect(0, 0, 208, editorRowHeight))
    textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    textField.font = editorFont()
    textField.text = getter()
    textField.onAction do():
        setter(textField.text)

    result.addSubview(textField)

proc newVecPropertyView[T](setter: proc(s: T), getter: proc(): T): PropertyEditorView =
    result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    const vecLen = high(T) + 1

    let horLayout = newHorizontalLayout(newRect(0, 0, 208, editorRowHeight))
    horLayout.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    result.addSubview(horLayout)

    proc complexSetter() =
        var val : TVector[vecLen, Coord]
        for i in 0 ..< horLayout.subviews.len:
            try:
                val[i] = TextField(horLayout.subviews[i]).text.parseFloat()
            except ValueError:
                return
        setter(val)

    let val = getter()
    for i in 0 ..< vecLen:
        let textField = newNumericTextField(zeroRect)
        textField.font = editorFont()
        textField.text = toStr(val[i], textField.precision)
        textField.onAction complexSetter
        horLayout.addSubview(textField)

proc newColorPropertyView(setter: proc(s: Color), getter: proc(): Color): PropertyEditorView =
    result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    const vecLen = 3 + 1

    let colorView = View.new(newRect(0, 0, editorRowHeight, editorRowHeight))
    colorView.backgroundColor = getter()
    result.addSubview(colorView)

    var prevColor: Color

    let horLayout = newHorizontalLayout(newRect(editorRowHeight, 0, result.bounds.width - editorRowHeight, editorRowHeight))
    horLayout.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    result.addSubview(horLayout)

    proc complexSetter() =
        try:
            let c = newColor(
                TextField(horLayout.subviews[0]).text.parseFloat(),
                TextField(horLayout.subviews[1]).text.parseFloat(),
                TextField(horLayout.subviews[2]).text.parseFloat(),
                TextField(horLayout.subviews[3]).text.parseFloat(),
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
                gColorPicker.setFrameOrigin(newPoint(horLayout.frame.x+140+300, 0))

                let pickerCloseButton = Button.new(newRect(0, 0, 25, 25))
                pickerCloseButton.title = "x"
                pickerCloseButton.onAction do():
                    gColorPicker.removeFromSuperview()
                    gColorPicker = nil
                let pickerCancelButton = Button.new(newRect(0, 25, 25, 25))
                pickerCancelButton.title = "c"
                pickerCancelButton.onAction do():
                    TextField(horLayout.subviews[0]).text = $prevColor.r
                    TextField(horLayout.subviews[1]).text = $prevColor.g
                    TextField(horLayout.subviews[2]).text = $prevColor.b
                    TextField(horLayout.subviews[3]).text = $prevColor.a

                    setter(prevColor)
                    colorView.backgroundColor = prevColor
                    gColorPicker.colorHasChanged(rgbToHSV(prevColor.r, prevColor.g, prevColor.b))

                gColorPicker.addSubview(pickerCloseButton)
                gColorPicker.addSubview(pickerCancelButton)
                horLayout.window.addSubview(gColorPicker)

                gColorPicker.colorHasChanged(rgbToHSV(c.r, c.g, c.b))
                gColorPicker.onColorSelected = proc(pc: Color) =
                    TextField(horLayout.subviews[0]).text = $pc.r
                    TextField(horLayout.subviews[1]).text = $pc.g
                    TextField(horLayout.subviews[2]).text = $pc.b
                    TextField(horLayout.subviews[3]).text = $pc.a

                    setter(pc)
                    colorView.backgroundColor = pc

        except ValueError:
            discard

    template toVector(c: Color): Vector4 = newVector4(c.r, c.g, c.b, c.a)

    for i in 0 ..< vecLen:
        let textField = newNumericTextField(zeroRect)
        textField.font = editorFont()
        textField.text = toStr(getter().toVector[i], textField.precision)
        textField.onAction complexSetter
        horLayout.addSubview(textField)

proc newSizePropertyView(setter: proc(s: Size), getter: proc(): Size): PropertyEditorView =
    newVecPropertyView(
        proc(v: Vector2) = setter(newSize(v.x, v.y)),
        proc(): Vector2 =
            let s = getter()
            result = newVector2(s.width, s.height)
            )

proc newPointPropertyView(setter: proc(s: Point), getter: proc(): Point): PropertyEditorView =
    newVecPropertyView(
        proc(v: Vector2) = setter(newPoint(v.x, v.y)),
        proc(): Vector2 =
            let s = getter()
            result = newVector2(s.x, s.y)
            )

when not defined(android) and not defined(ios):
    proc newImagePropertyView(setter: proc(s: Image), getter: proc(): Image): PropertyEditorView =
        let pv = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
        let b = Button.new(newRect(0, 0, 208, editorRowHeight))
        b.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        b.title = "Open image..."
        b.onAction do():
            when defined(js):
                alert("Files can be opened only in native editor version")
            elif defined(emscripten):
                discard
            else:
                let path = callDialogFileOpen("Select Image")
                if not path.isNil:
                    setter(imageWithContentsOfFile(path))
                    if not pv.onChange.isNil:
                        pv.onChange()

        result = pv
        result.addSubview(b)

    registerPropertyEditor(newImagePropertyView)

    type ImagePercent = tuple
        s: Image
        v: float32
    proc newMaterialImagePropertyView(setter: proc(t: ImagePercent), getter: proc(): ImagePercent ): PropertyEditorView =
        let pv = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))

        var loadedImage = getter().s
        let imgButton = newImageButton(pv, newPoint(0, 0), newSize(editorRowHeight, editorRowHeight), loadedImage)

        let bOpen = Button.new(newRect(30, 0, 70, editorRowHeight))
        bOpen.title = "Open"
        bOpen.onAction do():
            when defined(js):
                alert("Files can be opened only in native editor version")
            elif defined(emscripten):
                discard
            else:
                let path = callDialogFileOpen("Select Image")
                if not path.isNil:
                    loadedImage = imageWithContentsOfFile(path)
                    var t:ImagePercent
                    t.s = loadedImage
                    t.v = getter().v.float32
                    setter(t)
                    imgButton.image = loadedImage
                    if not pv.onChange.isNil:
                        pv.onChange()

        let bRemove = Button.new(newRect(105, 0, 70, editorRowHeight))
        bRemove.title = "Remove"
        bRemove.onAction do():
            if not getter().s.isNil:
                var simg = getter().s.SelfContainedImage
                let c = currentContext()
                let gl = c.gl
                gl.deleteFramebuffer(simg.framebuffer)
                gl.deleteTexture(simg.texture)
                simg.framebuffer = invalidFrameBuffer
                simg.texture = invalidTexture
                simg = nil
                var t:ImagePercent
                t.s = nil
                t.v = getter().v.float32
                setter(t)
                imgButton.image = nil
                loadedImage = nil
                if not pv.onChange.isNil:
                    pv.onChange()

        result = pv
        result.addSubview(bOpen)
        result.addSubview(bRemove)

        if not currEditedNode.isNil:
            let meshComp = currEditedNode.componentIfAvailable(MeshComponent)
            if not meshComp.isNil:
                let tf = newNumericTextField(newRect(180, 0, 50, editorRowHeight))
                tf.text = toStr(getter().v, tf.precision)
                tf.onAction do():
                    try:
                        var v: float32
                        fromStr(tf.text, v)
                        var t:ImagePercent
                        t.s = if not loadedImage.isNil: loadedImage else: getter().s
                        t.v = v.float32
                        setter(t)
                        if not pv.onChange.isNil:
                            pv.onChange()
                    except ValueError:
                        discard
                result.addSubview(tf)

    registerPropertyEditor(newMaterialImagePropertyView)

proc newNodePropertyView(editedNode: Node, setter: proc(s: Node), getter: proc(): Node): PropertyEditorView =
    currEditedNode = editedNode

    let textField = newTextField(newRect(0, 0, 200, editorRowHeight))
    textField.font = editorFont()
    textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    let n = getter()
    if n.isNil or n.name.isNil:
        textField.text = "nil"
    else:
        textField.text = n.name
    textField.onAction do():
        setter(editedNode.sceneView.rootNode.findNode(textField.text))
    result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    result.addSubview(textField)

proc newBoolPropertyView(editedNode: Node, setter: proc(s: bool), getter: proc(): bool): PropertyEditorView =
    currEditedNode = editedNode

    let pv = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    let cb = newCheckbox(newRect(0, 0, editorRowHeight, editorRowHeight))
    cb.value = if getter(): 1 else: 0
    cb.onAction do():
        setter(cb.boolValue)

        if not pv.onChange.isNil:
            pv.onChange()

    result = pv
    result.addSubview(cb)

proc newQuaternionPropertyView(setter: proc(s: Quaternion), getter: proc(): Quaternion): PropertyEditorView =
    result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    const vecLen = 3

    let horLayout = newHorizontalLayout(newRect(0, 0, 208, editorRowHeight))
    horLayout.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    result.addSubview(horLayout)

    proc complexSetter() =
        var val: Quaternion
        var euler = newVector3(0.0, 0.0, 0.0)
        for i in 0 ..< horLayout.subviews.len:
            try:
                euler[i] = TextField(horLayout.subviews[i]).text.parseFloat()
            except ValueError:
                return

        val = newQuaternionFromEulerYXZ(euler.x, euler.y, euler.z)
        setter(val)

    let val = getter()
    let euler = val.eulerAngles()

    for i in 0 ..< vecLen:
        let textField = newNumericTextField(zeroRect)
        textField.font = editorFont()
        textField.text = toStr(-euler[i], textField.precision)
        textField.onAction complexSetter
        horLayout.addSubview(textField)

proc newEnumPropertyView(setter: proc(s: EnumValue), getter: proc(): EnumValue): PropertyEditorView =
    let pv = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    var val = getter()
    var items = newSeq[string]()
    for k, v in val.possibleValues:
        items.add(k)

    sort(items, system.cmp)
    var enumChooser = newPopupButton(pv,
        newPoint(0.0, 0.0), newSize(208, editorRowHeight),
        items, val.curValue)

    enumChooser.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}

    enumChooser.onAction do():
        val.curValue = val.possibleValues[enumChooser.selectedItem()]
        setter(val)
        if not pv.changeInspector.isNil:
            pv.changeInspector()

    result = pv

template closureScope*(body: untyped): stmt = (proc() = body)()
proc newScalarSeqPropertyView[T](setter: proc(s: seq[T]), getter: proc(): seq[T]): PropertyEditorView =
    var val = getter()
    var height = val.len() * 26 + 26
    let pv = PropertyEditorView.new(newRect(0, 0, 208, height.Coord))

    proc onValChange() =
        setter(val)

    proc onSeqChange() =
        onValChange()
        if not pv.changeInspector.isNil:
            pv.changeInspector()

    var y = 0.Coord
    for i in 0 ..< val.len:
        closureScope:
            let index = i
            let tf = newNumericTextField(newRect(0.Coord, y, 150, editorRowHeight))
            tf.font = editorFont()
            pv.addSubview(tf)
            tf.text = toStr(val[i], tf.precision)
            tf.onAction do():
                if index < val.len:
                    fromStr(tf.text, val[index])
                    onValChange()

            let removeButton = Button.new(newRect(153, y, editorRowHeight, editorRowHeight))
            removeButton.title = "-"
            pv.addSubview(removeButton)
            removeButton.onAction do():
                val.delete(index)
                onSeqChange()

            y += 18

    let addButton = Button.new(newRect(153, y, editorRowHeight, editorRowHeight))
    addButton.title = "+"
    pv.addSubview(addButton)
    addButton.onAction do():
        val.add(0.0)
        onSeqChange()

    result = pv

# proc newSeqPropertyView[I: static[int], T](setter: proc(s: seq[TVector[I, T]]), getter: proc(): seq[TVector[I, T]]): PropertyEditorView =
proc newSeqPropertyView[T](setter: proc(s: seq[T]), getter: proc(): seq[T]): PropertyEditorView =
    var val = getter()
    var height = val.len() * 26 + 26
    let pv = PropertyEditorView.new(newRect(0, 0, 208, height.Coord))
    const vecLen = high(T) + 1

    proc onValChange() =
        setter(val)

    proc onSeqChange() =
        onValChange()
        if not pv.changeInspector.isNil:
            pv.changeInspector()

    var x = 0.Coord
    var y = 0.Coord
    for i in 0 ..< val.len:
        closureScope:
            let index = i
            var vecVal = val[i]

            x = 0.Coord
            for j in 0 ..< vecLen:
                closureScope:
                    let jIndex = j
                    let tf = newNumericTextField(newRect(x, y, 35, editorRowHeight))
                    tf.font = editorFont()
                    x += 37
                    pv.addSubview(tf)
                    tf.text = toStr(vecVal[j], tf.precision)
                    tf.onAction do():
                        if index < val.len:
                            val[index][jIndex] = tf.text.parseFloat()
                            onValChange()

            let removeButton = Button.new(newRect(x, y, editorRowHeight, editorRowHeight))
            removeButton.title = "-"
            pv.addSubview(removeButton)
            removeButton.onAction do():
                val.delete(index)
                onSeqChange()

            y += editorRowHeight + 2

    let addButton = Button.new(newRect(x, y, editorRowHeight, editorRowHeight))
    addButton.title = "+"
    pv.addSubview(addButton)
    addButton.onAction do():
        var newVal : TVector[vecLen, Coord]
        val.add(newVal)
        onSeqChange()

    result = pv

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
registerPropertyEditor(newQuaternionPropertyView)
registerPropertyEditor(newEnumPropertyView)
registerPropertyEditor(newScalarSeqPropertyView[float])
registerPropertyEditor(newSeqPropertyView[TVector[4, Coord]])
registerPropertyEditor(newSeqPropertyView[TVector[5, Coord]])
