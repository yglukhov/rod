import nimx/[view, text_field, matrixes, image, button,
    linear_layout, property_visitor, numeric_text_field,
    slider, animation
]
import rod/component/[ae_composition]
import rod/property_editors/propedit_registry
import nimx/property_editors/standard_editors #used
import rod/[node, viewport, quaternion, rod_types]
import strutils, tables, times
import variant

const openDialogAvailable = not defined(android) and not defined(ios) and not defined(emscripten)

when defined(js):
    from dom import alert
elif openDialogAvailable:
    import os_files/dialog

template toStr(v: SomeFloat, precision: uint): string = formatFloat(v, ffDecimal, precision)
template toStr(v: SomeInteger): string = $v

template fromStr(v: string, t: var SomeFloat) = t = v.parseFloat()
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
    if n.isNil or n.name.len == 0:
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
        let name = marker.name
        let label = newLabel(newRect(0, y, 100, 15))
        label.text = name
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

        animT[name] = compos.compositionNamed(name)
        animT[name].prepare(epochTime())

        closureScope:
            let mName = name
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

proc newCompositionPropertyView(setter: proc(s: Composition), getter: proc(): Composition): PropertyEditorView =
    result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight * 3))

    # let horLayout = newHorizontalLayout(newRect(0, 0, 208, editorRowHeight * 3))
    # horLayout.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    # result.addSubview(horLayout)

    let v = getter()
    var y = 0.0
    y += editorRowHeight
    var lbl = newLabel(newRect(0, y, 208, editorRowHeight))
    lbl.text = if v.isNil: "" else: v.url
    result.addSubview(lbl)
    y += editorRowHeight

    var open = newButton(newRect(0, y, 208, editorRowHeight))
    open.title = "open"
    open.onAction do():
        when openDialogAvailable:
            var di: DialogInfo
            # di.folder = e.currentProject.path
            di.kind = dkOpenFile
            di.filters = @[(name:"JCOMP", ext:"*.jcomp"), (name:"Json", ext:"*.json")]
            di.title = "Open composition"
            let path = di.show()
            if path.len > 0:
                setter(newComposition("file://" & path))

    result.addSubview(open)


registerPropertyEditor(newNodePropertyView)
registerPropertyEditor(newQuaternionPropertyView)
registerPropertyEditor(newAEMarkerPropertyView)
registerPropertyEditor(newCompositionPropertyView)
