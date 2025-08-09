import std/[strutils, tables, times, math]
import variant
import nimx/property_editors/[ standard_editors, propedit_registry ] #used
import nimx/[view, layout, text_field, matrixes, image, button, property_visitor, numeric_text_field,
    slider, animation, context, view_event_handling, event
]
import ../component/[ae_composition, rti]
import ../[node, viewport, quaternion, rod_types]


when defined(rodedit):
    import rod/property_editors/rodedit_editors

const openDialogAvailable = not defined(android) and not defined(ios) and not defined(emscripten)

when defined(js):
    from dom import alert
elif openDialogAvailable:
    import os_files/dialog

template toStr(v: SomeFloat, precision: uint): string = formatFloat(v, ffDecimal, precision)
template toStr(v: SomeInteger): string = $v

template fromStr(v: string, t: var SomeFloat) = t = v.parseFloat()
template fromStr(v: string, t: var SomeInteger) = t = v.parseInt()


when defined(rodedit):
    type ImagePercent* = tuple
        s: Image
        v: float32
    proc newMaterialImagePropertyView(setter: proc(t: ImagePercent) {.gcsafe.}, getter: proc(): ImagePercent {.gcsafe.}): PropertyEditorView =
        var loadedImage = getter().s
        let r = new(PropertyEditorView)
        r.makeLayout:
            - Button as imgBtn:
                top == super
                leading == super
                width == 128
                height == 128
                hasBezel: false
                image: loadedImage

            - Button as open:
                top == prev.bottom
                leading == super
                height == editorRowHeight
                width == super.width * 0.5
                title: "open"
                onAction:
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
                            imgBtn.image = loadedImage
                            if not r.onChange.isNil:
                                r.onChange()
            - Button as remove:
                top == prev
                leading == prev.trailing
                width == prev
                title: "remove"
                onAction:
                    if not getter().s.isNil:
                        var t:ImagePercent
                        t.s = nil
                        t.v = getter().v.float32
                        setter(t)
                        imgBtn.image = nil
                        loadedImage = nil
                        if not r.onChange.isNil:
                            r.onChange()

            - NumericTextField as tf:
                top == prev.bottom
                leading == super
                trailing == super
                bottom == super
                height == editorRowHeight
                onAction:
                    try:
                        var v: float32
                        fromStr(tf.text, v)
                        var t:ImagePercent
                        t.s = if not loadedImage.isNil: loadedImage else: getter().s
                        t.v = v.float32
                        setter(t)
                        if not r.onChange.isNil:
                            r.onChange()
                    except ValueError:
                        discard

        result = r

    registerPropertyEditor(newMaterialImagePropertyView)


# proc newAEMarkerPropertyView(setter: proc(s: AEComposition) {.gcsafe.}, getter: proc(): AEComposition {.gcsafe.}): PropertyEditorView {.gcsafe.} =
#     let compos = getter()
#     result = PropertyEditorView.new(newRect(0, 0, 208, (editorRowHeight * 3 + 10.0) * compos.markers.len().float + 20))
#     var y = 0.0

#     var animT = initTable[string, Animation]()

#     let a = newAnimation()
#     a.numberOfLoops = 1
#     a.finished = true

#     for marker in compos.markers:
#         y += 10.0
#         let name = marker.name
#         let label = newLabel(newRect(0, y, 100, 15))
#         label.text = name
#         label.textColor = newGrayColor(0.9)
#         result.addSubview(label)
#         label.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
#         y += editorRowHeight

#         let slider = new(Slider, newRect(0, y, 200, editorRowHeight))
#         result.addSubview(slider)
#         slider.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
#         y += editorRowHeight

#         let durationLabel = newLabel(newRect(0, y, 30, 15))
#         durationLabel.text = ($marker.duration).substr(0, 4)
#         durationLabel.textColor = newGrayColor(0.9)
#         result.addSubview(durationLabel)

#         let progLabel = newNumericTextField(newRect(45, y, 50, 15))
#         progLabel.font = editorFont()
#         progLabel.text = "0.0"
#         result.addSubview(progLabel)

#         let goBttn = newButton(newRect(100, y, 40, 15))
#         goBttn.title = "go"
#         result.addSubview(goBttn)

#         let playBttn = newButton(newRect(140, y, 40, 15))
#         playBttn.title = "play"
#         result.addSubview(playBttn)
#         y += editorRowHeight

#         animT[name] = compos.compositionNamed(name)
#         animT[name].prepare(epochTime())

#         closureScope:
#             let mName = name
#             let sl = slider
#             let pl = progLabel
#             let gb = goBttn
#             let pb = playBttn
#             sl.onAction do():
#                 let anim = animT.getOrDefault(mName)
#                 if not anim.isNil:
#                     anim.onProgress(sl.value)
#                     pl.text = ($sl.value).substr(0, 4)

#             gb.onAction do():
#                 let anim = animT.getOrDefault(mName)
#                 if not anim.isNil:
#                     anim.onProgress(pl.text.parseFloat())
#                     sl.value = pl.text.parseFloat()

#             pb.onAction do():
#                 let anim = animT.getOrDefault(mName)
#                 if not anim.isNil:
#                     if not a.finished:
#                         pb.title = "play"
#                         a.cancel()

#                     else:
#                         pb.title = "stop"
#                         a.loopDuration = anim.loopDuration

#                         a.onAnimate = proc(p:float)=
#                             anim.onProgress(p)
#                             sl.value = p
#                             pl.text = ($p).substr(0, 4)

#                         compos.node.sceneView.addAnimation(a)
#                         a.onComplete() do():
#                             pb.title = "play"

    # result = PropertyEditorView.new(newRect(0, 0, 208, editorRowHeight * 3))

    # # let horLayout = newHorizontalLayout(newRect(0, 0, 208, editorRowHeight * 3))
    # # horLayout.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
    # # result.addSubview(horLayout)

    # let v = getter()
    # var y = 0.0
    # y += editorRowHeight
    # var lbl = newLabel(newRect(0, y, 208, editorRowHeight))
    # lbl.text = if v.isNil: "" else: v.url
    # result.addSubview(lbl)
    # y += editorRowHeight

    # var open = newButton(newRect(0, y, 208, editorRowHeight))
    # open.title = "open"
    # open.onAction do():
    #     when openDialogAvailable:
    #         var di: DialogInfo
    #         # di.folder = e.currentProject.path
    #         di.kind = dkOpenFile
    #         di.filters = @[(name:"JCOMP", ext:"*.jcomp"), (name:"Json", ext:"*.json")]
    #         di.title = "Open composition"
    #         let path = di.show()
    #         if path.len > 0:
    #             setter(newComposition("file://" & path))

    # result.addSubview(open)


proc newQuaternionPropertyView(setter: proc(s: Quaternion) {.gcsafe.}, getter: proc(): Quaternion {.gcsafe.}): PropertyEditorView =
    proc complexSetter() {.gcsafe.}

    let val = getter()
    let euler = val.eulerAngles()

    result = PropertyEditorView.new()
    result.makeLayout:
        height == editorRowHeight
        - NumericTextField as xComp:
            origin == super.origin
            width == super.width * 0.33
            height == super.height
            font: editorFont()
            text: toStr(-euler[0], xComp.precision)
            onAction: complexSetter()
        - NumericTextField as yComp:
            y == super.y
            x == prev.trailing
            width == super.width * 0.33
            height == super.height
            font: editorFont()
            text: toStr(-euler[1], yComp.precision)
            onAction: complexSetter()
        - NumericTextField as zComp:
            y == super.y
            x == prev.trailing
            width == super.width * 0.33
            height == super.height
            font: editorFont()
            text: toStr(-euler[2], zComp.precision)
            onAction: complexSetter()

    proc complexSetter() {.gcsafe.} =
        try:
            var euler = newVector3(xComp.text.parseFloat(), yComp.text.parseFloat(), zComp.text.parseFloat())
            var val = newQuaternionFromEulerYXZ(euler.x, euler.y, euler.z)
            setter(val)
        except ValueError:
            return

proc newCompositionPropertyView(setter: proc(s: rod_types.Composition) {.gcsafe.}, getter: proc(): rod_types.Composition {.gcsafe.}): PropertyEditorView =
    let compos = getter()
    result = PropertyEditorView.new()
    result.makeLayout:
        height == editorRowHeight * 2
        - Label as label:
            origin == super.origin
            width == super
            height == editorRowHeight @ WEAK
        - Button:
            x == super.x
            y == prev.bottom
            width == super
            height == editorRowHeight @ WEAK
            title: "open"
            onAction:
                when openDialogAvailable:
                    var di: DialogInfo
                    # di.folder = e.currentProject.path
                    di.kind = dkOpenFile
                    di.filters = @[(name:"JCOMP", ext:"*.jcomp"), (name:"Json", ext:"*.json")]
                    di.title = "Open composition"
                    let path = di.show()
                    if path.len > 0:
                        setter(newComposition("file://" & path))

    label.text = if compos.isNil: "" else: compos.url

# TODO: Do we really need this newNodePropertyView????
proc newNodePropertyView(setter: proc(s: Node) {.gcsafe.}, getter: proc(): Node {.gcsafe.}): PropertyEditorView =
    # let editedNode = editedObject.get(Node)
    let n = getter()
    result = PropertyEditorView.new()
    result.makeLayout:
        height == editorRowHeight
        - TextField as tf:
            font: editorFont()
            onAction:
                setter(n.sceneView.rootNode.findNode(tf.text))

    if n.isNil or n.name.len == 0:
        tf.text = "nil"
    else:
        tf.text = n.name

registerPropertyEditor(newNodePropertyView)
registerPropertyEditor(newQuaternionPropertyView)
# registerPropertyEditor(newAEMarkerPropertyView)
registerPropertyEditor(newCompositionPropertyView)
