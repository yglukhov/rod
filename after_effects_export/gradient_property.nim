import after_effects
import json

proc getGradientColors*(gradientOverlay: PropertyGroup, comp: Composition): array[2, array[4, float]] =
    const undoGroupId = "__rod_export_script_undo_group__"
    app.beginUndoGroup(undoGroupId)

    let color = [1.0, 1.0, 1.0]
    let tempLayer = comp.layers.addSolid(color, "temp", 255, 255, 1.0)

    tempLayer.selected = true
    app.executeCommand(app.findMenuCommandId("Gradient Overlay"))
    tempLayer.selected = false
    gradientOverlay.property("Colors").selected = true
    app.executeCommand(app.findMenuCommandId("Copy"))
    gradientOverlay.property("Colors").selected = false
    tempLayer.propertyGroup("Layer Styles").propertyGroup("Gradient Overlay").selected = true
    app.executeCommand(app.findMenuCommandId("Paste"))
    tempLayer.propertyGroup("Layer Styles").propertyGroup("Gradient Overlay").selected = false
    tempLayer.property("Position", array[3, float32]).setValue([0'f32, 0, 0])
    tempLayer.property("anchorPoint", array[3, float32]).setValue([0'f32, 0, 0])

    let newComp = comp.layers.precompose(@[1], "tempComp", true)
    let tempLayerText = comp.layers.addText()
    let tempText = tempLayerText.propertyGroup("Text").property("Source Text", TextDocument)

    tempText.expression = "thisComp.layer(\"tempComp\").sampleImage([0, 0], [0.5, 0.5], true).toSource()"
    for i in 0 ..< 10000000:
        if $tempText.valueAtTime(0, false).text != "[0, 0, 0, 0]": break

    let c0 = parseJson($tempText.value.text)
    result[1] = [c0[0].getFloat(), c0[1].getFloat(), c0[2].getFloat(), c0[3].getFloat()]

    tempText.expression = "thisComp.layer(\"tempComp\").sampleImage([254, 254], [0.5, 0.5], true).toSource()"
    for i in 0 ..< 10000000:
        if $tempText.valueAtTime(0, false).text != "[0, 0, 0, 0]": break

    let c1 = parseJson($tempText.value.text)
    result[0] = [c1[0].getFloat(), c1[1].getFloat(), c1[2].getFloat(), c1[3].getFloat()]

    app.endUndoGroup()
    app.undo(undoGroupId)