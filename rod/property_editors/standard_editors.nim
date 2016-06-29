import strutils

import nimx.view
import nimx.text_field
import nimx.matrixes
import nimx.image
import nimx.button
import nimx.font
import nimx.linear_layout
import nimx.property_visitor
import nimx.numeric_text_field

import nimx.property_editors.standard_editors
import rod.property_editors.propedit_registry
import rod.node
import rod.viewport
import rod.quaternion
import rod.component.mesh_component

import variant

when defined(js):
    from dom import alert
elif not defined(android) and not defined(ios) and not defined(emscripten):
    import native_dialogs

template toStr(v: SomeReal, precision: uint): string = formatFloat(v, ffDecimal, precision)
template toStr(v: SomeInteger): string = $v

template fromStr(v: string, t: var SomeReal) = t = v.parseFloat()
template fromStr(v: string, t: var SomeInteger) = t = v.parseInt()


when not defined(android) and not defined(ios):
    type ImagePercent = tuple
        s: Image
        v: float32
    proc newMaterialImagePropertyView(editedObject: Variant, setter: proc(t: ImagePercent), getter: proc(): ImagePercent): PropertyEditorView =
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

        let editedNode = editedObject.get(Node)
        let meshComp = editedNode.componentIfAvailable(MeshComponent)
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

proc newNodePropertyView(editedObject: Variant, setter: proc(s: Node), getter: proc(): Node): PropertyEditorView =
    let textField = newTextField(newRect(0, 0, 200, editorRowHeight))
    textField.font = editorFont()
    textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    let n = getter()
    if n.isNil or n.name.isNil:
        textField.text = "nil"
    else:
        textField.text = n.name
    let editedNode = editedObject.get(Node)
    textField.onAction do():
        setter(editedNode.sceneView.rootNode.findNode(textField.text))
    result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))
    result.addSubview(textField)

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

registerPropertyEditor(newNodePropertyView)
registerPropertyEditor(newQuaternionPropertyView)
