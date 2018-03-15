import strutils, tables, times

import nimx.view
import nimx.text_field
import nimx.matrixes
import nimx.image
import nimx.button
import nimx.font
import nimx.linear_layout
import nimx.property_visitor
import nimx.numeric_text_field
import nimx.slider
import nimx.animation

import nimx.property_editors.standard_editors
import rod.property_editors.propedit_registry
import rod.node
import rod.viewport
import rod.quaternion
import rod.component.mesh_component
import rod.component.ae_composition
import rod.component.nine_part

import variant

when defined(js):
    from dom import alert
elif not defined(android) and not defined(ios) and not defined(emscripten):
    import os_files.dialog

template toStr(v: SomeReal, precision: uint): string = formatFloat(v, ffDecimal, precision)
template toStr(v: SomeInteger): string = $v

template fromStr(v: string, t: var SomeReal) = t = v.parseFloat()
template fromStr(v: string, t: var SomeInteger) = t = v.parseInt()


when not defined(android) and not defined(ios):
    type ImagePercent = tuple
        s: Image
        v: float32
    proc newMaterialImagePropertyView(setter: proc(t: ImagePercent), getter: proc(): ImagePercent): PropertyEditorView =
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
                var di: DialogInfo
                di.title = "Select texture"
                di.kind = dkOpenFile
                di.filters = @[(name:"PNG", ext:"*.png")]
                let path = di.show()
                if path.len > 0:
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

proc newAEMarkerPropertyView(setter: proc(s: AEComposition), getter: proc(): AEComposition): PropertyEditorView =
    let compos = getter()
    result = PropertyEditorView.new(newRect(0, 0, 208, (editorRowHeight * 3 + 10.0) * compos.markers.len().float + 20))
    var y = 0.0

    var animT = initTable[string, Animation]()

    let a = newAnimation()
    a.numberOfLoops = 1
    a.finished = true

    for marker in compos.markers:
        y += 10.0
        let label = newLabel(newRect(0, y, 100, 15))
        label.text = marker.name
        label.textColor = newGrayColor(0.9)
        result.addSubview(label)
        label.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        y += editorRowHeight

        let slider = new(Slider, newRect(0, y, 200, editorRowHeight))
        result.addSubview(slider)
        slider.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
        y += editorRowHeight

        let durationLabel = newLabel(newRect(0, y, 30, 15))
        durationLabel.text = ($marker.duration).substr(0, 4)
        durationLabel.textColor = newGrayColor(0.9)
        result.addSubview(durationLabel)

        let progLabel = newNumericTextField(newRect(45, y, 50, 15))
        progLabel.font = editorFont()
        progLabel.text = "0.0"
        result.addSubview(progLabel)

        let goBttn = newButton(newRect(100, y, 40, 15))
        goBttn.title = "go"
        result.addSubview(goBttn)

        let playBttn = newButton(newRect(140, y, 40, 15))
        playBttn.title = "play"
        result.addSubview(playBttn)
        y += editorRowHeight

        animT[marker.name] = compos.compositionNamed(marker.name)
        animT[marker.name].prepare(epochTime())

        closureScope:
            let mName = marker.name
            let sl = slider
            let pl = progLabel
            let gb = goBttn
            let pb = playBttn
            sl.onAction do():
                let anim = animT.getOrDefault(mName)
                if not anim.isNil:
                    anim.onProgress(sl.value)
                    pl.text = ($sl.value).substr(0, 4)

            gb.onAction do():
                let anim = animT.getOrDefault(mName)
                if not anim.isNil:
                    anim.onProgress(pl.text.parseFloat())
                    sl.value = pl.text.parseFloat()

            pb.onAction do():
                let anim = animT.getOrDefault(mName)
                if not anim.isNil:
                    if not a.finished:
                        pb.title = "play"
                        a.cancel()

                    else:
                        pb.title = "stop"
                        a.loopDuration = anim.loopDuration

                        a.onAnimate = proc(p:float)=
                            anim.onProgress(p)
                            sl.value = p
                            pl.text = ($p).substr(0, 4)

                        compos.node.sceneView.addAnimation(a)
                        a.onComplete() do():
                            pb.title = "play"

registerPropertyEditor(newNodePropertyView)
registerPropertyEditor(newQuaternionPropertyView)
registerPropertyEditor(newAEMarkerPropertyView)

import logging
import nimx / [ button, image_preview, view, numeric_text_field, context ]
type NinePartImagePreview* = ref object of ImagePreview
    margine*: NinePartMargine
    onMargineChange: proc()

proc addMargineTextField(v: NinePartImagePreview, r: Rect, value, name: string, cb: proc(val: float32)) =
    let ll = newLabel(parent = v, position = r.origin, text = name)
    let l = newNumericTextField(newRect(r.origin.x + 10.0, r.origin.y, 50, 20), 1)
    l.text = value
    v.addSubview(l)
    l.onAction do():
        cb(l.text.parseFloat())
        if not v.onMargineChange.isNil:
            v.onMargineChange()

proc newNinePartImagePreview*(r: Rect, img: Image, margine: NinePartMargine): NinePartImagePreview =
    result.new()
    result.image = img
    result.margine = margine
    result.init(r)

    let oldBoundsSize = result.bounds.size
    result.setFrameSize(newSize(oldBoundsSize.width, oldBoundsSize.height + 90))

    let res = result
    res.addMargineTextField(newRect(5.0, oldBoundsSize.height, 50, 20), $res.margine.left, "l") do(val: float32): res.margine.left = val
    res.addMargineTextField(newRect(70.0, oldBoundsSize.height, 50, 20), $res.margine.right, "r") do(val: float32): res.margine.right = val
    res.addMargineTextField(newRect(5.0, oldBoundsSize.height + 25, 50, 20), $res.margine.top, "t") do(val: float32): res.margine.top = val
    res.addMargineTextField(newRect(70.0, oldBoundsSize.height + 25, 50, 20), $res.margine.bottom, "b") do(val: float32): res.margine.bottom = val


method draw*(v: NinePartImagePreview, r: Rect) =
    procCall v.ImagePreview.draw(r)
    let c = currentContext()

    var margineRect: Rect
    margineRect.origin = newPoint(v.imageRect.origin.x + v.margine.left, v.imageRect.origin.y + v.margine.top)
    margineRect.size = newSize(v.imageRect.origin.x + v.imageRect.size.width - v.margine.right - margineRect.origin.x,
        v.imageRect.origin.y + v.imageRect.size.height - v.margine.bottom - margineRect.origin.y)
    c.fillColor = newColor(1.0, 0.0, 0.0, 0.5)
    c.drawRect(margineRect)


proc newNinePartPropertyView(setter: proc(s: NinePart), getter: proc(): NinePart): PropertyEditorView =
    var ninePart = getter()
    var pv: PropertyEditorView
    if not ninePart.image.isNil:
        let previewSize = 48.0
        pv = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight + 6 + previewSize))

        let imgButton = newImageButton(pv, newPoint(0, editorRowHeight + 3), newSize(previewSize, previewSize), ninePart.image)
        imgButton.onAction do():
            let imgPreview = newNinePartImagePreview(newRect(0, 0, 200, 200), ninePart.image, ninePart.margine)
            imgPreview.popupAtPoint(pv, newPoint(-10, 0))
            imgPreview.onMargineChange = proc() =
                ninePart.margine = imgPreview.margine
                setter(ninePart)

        let label = newLabel(newRect(previewSize + 5, editorRowHeight + 5 + editorRowHeight, 100, 15))
        label.text = "S: " & $int(ninePart.image.size.width) & " x " & $int(ninePart.image.size.height)
        label.textColor = newGrayColor(0.9)
        pv.addSubview(label)

        let removeButton = Button.new(newRect(previewSize + 5, editorRowHeight + 3, editorRowHeight, editorRowHeight))
        removeButton.title = "-"
        pv.addSubview(removeButton)
        removeButton.onAction do():
            setter(nil)
            if not pv.onChange.isNil:
                pv.onChange()
            if not pv.changeInspector.isNil:
                pv.changeInspector()
    else:
        pv = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight))

    let b = Button.new(newRect(0, 0, 208, editorRowHeight))
    b.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    b.title = "Open image..."
    b.onAction do():
        when defined(js):
            alert("Files can be opened only in native editor version")
        elif defined(emscripten):
            discard
        else:
            var di: DialogInfo
            di.title = "Select image"
            di.kind = dkOpenFile
            di.filters = @[(name:"PNG", ext:"*.png")]
            let path = di.show()
            echo "get path (", path, ")", path.len > 0
            if path.len > 0:

                try:
                    ninePart.image = imageWithContentsOfFile(path)
                except:
                    info "Image could not be loaded: ", path
                if not ninePart.image.isNil:
                    setter(ninePart)
                    if not pv.onChange.isNil:
                        pv.onChange()
                    if not pv.changeInspector.isNil:
                        pv.changeInspector()

    result = pv
    result.addSubview(b)

registerPropertyEditor(newNinePartPropertyView)
