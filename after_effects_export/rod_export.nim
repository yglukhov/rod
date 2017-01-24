import tables, dom, math
import after_effects
import times
import json
import algorithm
import strutils
import sequtils
import nimx.matrixes, nimx.pathutils
import rod.quaternion
import rod.utils.text_helpers

type File = after_effects.File

const exportSampledAnimations = true
const exportKeyframeAnimations = false

const exportedVersion = 1

const useObsoleteNullLayerCheck = false # Flip this if you have problems with exporting null layers

proc getObjectsWithTypeFromCollection*(t: typedesc, collection: openarray[Item], typeName: string): seq[t] =
    for i in collection:
        if i.jsObjectType == typeName:
            result.add(cast[t](i))

proc getSelectedCompositions(): seq[Composition] =
    getObjectsWithTypeFromCollection(Composition, app.project.selection, "CompItem")

var logTextField: EditText

proc `&=`(s, a: cstring) {.importcpp: "# += #".}

proc logi(args: varargs[string, `$`]) =
    for i in args:
        logTextField.text &= i
    logTextField.text &= "\n"

proc shouldSerializeLayer(layer: Layer): bool = return layer.enabled

template quaternionWithZRotation(zAngle: float32): Quaternion = newQuaternion(zAngle, newVector3(0, 0, 1))
template quaternionWithEulerRotation(euler: Vector3): Quaternion = newQuaternionFromEulerXYZ(euler.x, euler.y, euler.z)

let bannedPropertyNames = ["Time Remap", "Marker", "Checkbox", "Value/Offset/Random Max", "Slider", "Source Text"]

type PropertyDescription = ref object
    name: string
    fullyQualifiedName: string
    property: AbstractProperty
    valueAtTime: proc(time: float): JsonNode
    keyValue: proc(k: int): JsonNode
    initialValue: proc(): JsonNode
    separatedProperties: seq[AbstractProperty]

var gCompExportPath = ""
var gExportFolderPath = ""
var gAnimatedProperties = newSeq[PropertyDescription]()
var transitiveEffects = false

var layerNames = initTable[int, string]()
var resourcePaths: seq[string] = @[]

proc mangledName(layer: Layer): string =
    result = layerNames.getOrDefault(layer.index)
    if result.len == 0:
        result = $layer.name
        if result == $layer.containingComp.name:
            result &= "$" & $layer.index
        else:
            for v in values(layerNames):
                if result == v:
                    result &= "$" & $layer.index
                    break
        layerNames[layer.index] = result

proc fullyQualifiedPropName(layer: Layer, componentIndex: int, name: string, p: AbstractProperty): string =
    let layerName = layer.mangledName

    if componentIndex == -1:
        result = layerName & "." & name
    else:
        result = layerName & "." & $componentIndex & "." & name

proc isAnimated(p: AbstractProperty): bool =
    p.isTimeVarying and (not p.isSeparationLeader or not p.dimensionsSeparated)

proc newPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], mapper: proc(val: T): JsonNode = nil): PropertyDescription =
    if p.isNil:
        return

    result.new()
    result.name = name

    result.property = p
    if mapper.isNil:
        result.valueAtTime = proc(t: float): JsonNode =
            % p.valueAtTime(t)
        result.keyValue = proc(k: int): JsonNode =
            % p.keyValue(k)
    else:
        result.valueAtTime = proc(t: float): JsonNode =
            mapper(p.valueAtTime(t))
        result.keyValue = proc(k: int): JsonNode =
            mapper(p.keyValue(k))

    let vat = result.valueAtTime
    result.initialValue = proc(): JsonNode =
        vat(0)

    result.fullyQualifiedName = fullyQualifiedPropName(layer, componentIndex, name, p)


proc newPropDescSeparated[T](layer: Layer, componentIndex: int = -1, name: string, p: seq[Property[T]], mapper: proc(val: seq[T]): JsonNode = nil): PropertyDescription =
    if p.isNil:
        return

    result.new()
    result.name = name

    result.property = p[0]
    result.separatedProperties = @[]
    for i in 0 ..< p.len:
        result.separatedProperties.add(p[i])
    let r = result
    if mapper.isNil:
        result.valueAtTime = proc(t: float): JsonNode =
            result = newJArray()
            for sp in r.separatedProperties:
                result.add(%sp.toPropertyOfType(T).valueAtTime(t))
        result.keyValue = proc(k: int): JsonNode =
            result = newJArray()
            for sp in r.separatedProperties:
                result.add(%sp.toPropertyOfType(T).keyValue(k))
    else:
        result.valueAtTime = proc(t: float): JsonNode =
            var args = newSeq[T]()
            for sp in r.separatedProperties:
                args.add(sp.toPropertyOfType(T).valueAtTime(t))
            mapper(args)
        result.keyValue = proc(k: int): JsonNode =
            var args = newSeq[T]()
            for sp in r.separatedProperties:
                args.add(sp.toPropertyOfType(T).keyValue(k))
            mapper(args)

    let vat = result.valueAtTime
    result.initialValue = proc(): JsonNode =
        vat(0)

    result.fullyQualifiedName = fullyQualifiedPropName(layer, componentIndex, name, p[0])

proc addPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], mapper: proc(val: T): JsonNode = nil): PropertyDescription {.discardable.} =
    result = newPropDesc(layer, componentIndex, name, p, mapper)
    if not result.isNil and p.isAnimated:
        gAnimatedProperties.add(result)

proc addPropDesc[T](layer: Layer, componentIndex: int = -1, name: string, p: Property[T], defaultValue: T, mapper: proc(val: T): JsonNode = nil): PropertyDescription {.discardable.} =
    result = addPropDesc(layer, componentIndex, name, p, mapper)
    let vat = result.valueAtTime
    result.initialValue = proc(): JsonNode =
        let v = p.valueAtTime(0)
        if v != defaultValue:
            result = vat(0)

proc setInitialValueToResult(pd: PropertyDescription, res: JsonNode) =
    let v = pd.initialValue()
    if not v.isNil:
        res[pd.name] = v

proc getExportPathFromSourceFile(footageSource: FootageItem, file: File): string =
    var path = $footageSource.projectPath
    if path[^1] != '/': path &= "/"
    result = relativePathToPath("/" & gCompExportPath, path & $decodeURIComponent(file.name))

proc isSolidLayer(layer: Layer): bool =
    let source = FootageItem(layer.source)
    when useObsoleteNullLayerCheck:
        ($source.name).find("Null") != 0 and
            not source.mainSource.isNil and
            source.mainSource.jsObjectType == "SolidSource"
    else:
        not layer.nullLayer and not source.mainSource.isNil and
            source.mainSource.jsObjectType == "SolidSource"

proc isTextMarkerValid(layer: Layer): bool =
    let textMarker = layer.property("Marker", MarkerValue).valueAtTime(0).comment
    let textLayer = layer.propertyGroup("Text").property("Source Text", TextDocument).value.text

    if textMarker == textLayer or removeTextAttributes($textMarker) == textLayer:
        return true

proc getText(layer: Layer): string =
    let markerText = layer.property("Marker", MarkerValue).valueAtTime(0).comment
    let text = layer.propertyGroup("Text")
    let str = text.property("Source Text", TextDocument).value.text

    if not text.isNil:
        if markerText == "":
            return $str
    if layer.isTextMarkerValid():
        result = $markerText
    else:
        raise newException(Exception, "Marker is not valid for text: " & $str)

proc dumpPropertyTree(p: PropertyBase | Layer, indentLevel = 0) =
    ## This may come in handy to research After Effects property structure.
    var ln = ""
    for i in 0 ..< indentLevel: ln &= "    "

    when p is Layer:
        ln &= "+ layer: " & $p.name
    else:
        if p.isPropertyGroup:
            ln &= "+ group: "
        else:
            ln &= "- prop: "
        ln &= $p.name & ": " & $p.matchName
        if not p.isPropertyGroup:
            ln &= ": " & $p.toAbstractProperty().propertyValueType

    logi ln

    template dumpChildren(p: PropertyOwner) =
        for i in 0 ..< p.numProperties:
            dumpPropertyTree(p.property(i), indentLevel + 1)

    when p is Layer:
        dumpChildren(p)
    else:
        if p.isPropertyGroup:
            let p = p.toPropertyGroup()
            dumpChildren(p)

proc serializeEffect(layer: Layer, compIndex: int, p: PropertyGroup, renderableComponent: var bool): JsonNode =
    case $p.matchName
    of "ADBE Color Balance (HLS)":
        result = newJObject()
        let hue = addPropDesc(layer, compIndex, "hue", p.property("Hue", float)) do(v: float) -> JsonNode:
            %(v / 360)
        hue.setInitialValueToResult(result)
        let saturation = addPropDesc(layer, compIndex, "saturation", p.property("Saturation", float)) do(v: float) -> JsonNode:
            %(v / 100)
        saturation.setInitialValueToResult(result)
        let lightness = addPropDesc(layer, compIndex, "lightness", p.property("Lightness", float)) do(v: float) -> JsonNode:
            %(v / 100)
        lightness.setInitialValueToResult(result)
        result["_c"] = %"ColorBalanceHLS"

    of "ADBE Pro Levels2": # Channel levels (individual controls)
        proc separatedLevelValueAtTime(lvl: PropertyGroup, propName: string, t: float): Vector3 =
            result[0] = lvl.property("Red " & propName, float).valueAtTime(t, false)
            result[1] = lvl.property("Green " & propName, float).valueAtTime(t, false)
            result[2] = lvl.property("Blue " & propName, float).valueAtTime(t, false)

        proc levelsValueAtTime(lvl: PropertyGroup, t: float): JsonNode =
            result = newJObject()
            result["inWhite"] = % lvl.property("Input White", float).valueAtTime(t, false)
            result["inBlack"] = % lvl.property("Input Black", float).valueAtTime(t, false)
            result["inGamma"] = % lvl.property("Gamma", float).valueAtTime(t, false)
            result["outWhite"] = % lvl.property("Output White", float).valueAtTime(t, false)
            result["outBlack"] = % lvl.property("Output Black", float).valueAtTime(t, false)
            result["inWhiteV"] = %separatedLevelValueAtTime(lvl, "Input White", t)
            result["inBlackV"] = %separatedLevelValueAtTime(lvl, "Input Black", t)
            result["inGammaV"] = %separatedLevelValueAtTime(lvl, "Gamma", t)
            result["outWhiteV"] = %separatedLevelValueAtTime(lvl, "Output White", t)
            result["outBlackV"] = %separatedLevelValueAtTime(lvl, "Output Black", t)

        result = levelsValueAtTime(p, 0)
        result["_c"] = %"ChannelLevels"

        var propertyNameMap = {
            "Input White": "inWhite",
            "Input Black": "inBlack",
            "Gamma": "inGamma",
            "Output White": "outWhite",
            "Output Black": "outBlack",

            "Red Input White": "redInWhite",
            "Red Input Black": "redInBlack",
            "Red Gamma": "redInGamma",
            "Red Output White": "redOutWhite",
            "Red Output Black": "redOutBlack",
            "Green Input White": "greenInWhite",
            "Green Input Black": "greenInBlack",
            "Green Gamma": "greenInGamma",
            "Green Output White": "greenOutWhite",
            "Green Output Black": "greenOutBlack",
            "Blue Input White": "blueInWhite",
            "Blue Input Black": "blueInBlack",
            "Blue Gamma": "blueInGamma",
            "Blue Output White": "blueOutWhite",
            "Blue Output Black": "blueOutBlack",

        }.toTable()

        for n in ["Input White", "Input Black", "Gamma", "Output White", "Output Black"]:
            addPropDesc(layer, compIndex, propertyNameMap[n], p.property(n, float))
            addPropDesc(layer, compIndex, propertyNameMap["Red " & n], p.property("Red " & n, float))
            addPropDesc(layer, compIndex, propertyNameMap["Green " & n], p.property("Green " & n, float))
            addPropDesc(layer, compIndex, propertyNameMap["Blue " & n], p.property("Blue " & n, float))

    of "ADBE Numbers2": # Numbers
        renderableComponent = true
        result = newJObject()
        var color = p.property("Fill Color", Vector4).valueAtTime(0)
        result["color"] = %color
        result["fontSize"] = % p.property("Size", float).valueAtTime(0)
        result["_c"] = %"Text"

    of "ADBE Ramp": # Ramp
        result = newJObject()
        let startPoint = addPropDesc(layer, compIndex, "startPoint", p.property("Start of Ramp", Vector2))
        startPoint.setInitialValueToResult(result)

        let endPoint = addPropDesc(layer, compIndex, "endPoint", p.property("End of Ramp", Vector2))
        endPoint.setInitialValueToResult(result)

        let startColor = addPropDesc(layer, compIndex, "startColor", p.property("Start Color", Vector4))
        startColor.setInitialValueToResult(result)

        let endColor = addPropDesc(layer, compIndex, "endColor", p.property("End Color", Vector4))
        endColor.setInitialValueToResult(result)

        result["_c"] = %"GradientFill"

    of "ADBE Fill": # Fill
        result = newJObject()
        let startColor = addPropDesc(layer, compIndex, "color", p.property("Color", Vector4))
        startColor.setInitialValueToResult(result)
        result["_c"] = %"ColorFill"

    of "ADBE Tint": # Tint
        result = newJObject()
        let blackColor = addPropDesc(layer, compIndex, "black", p.property("Map Black To", Vector4))do(v: Vector4) -> JsonNode:
            %[v[0], v[1], v[2], 1.0]
        blackColor.setInitialValueToResult(result)

        let whiteColor = addPropDesc(layer, compIndex, "white", p.property("Map White To", Vector4))do(v: Vector4) -> JsonNode:
            %[v[0], v[1], v[2], 1.0]

        whiteColor.setInitialValueToResult(result)
        let amount = addPropDesc(layer, compIndex, "amount", p.property("Amount to Tint", float)) do(v: float) -> JsonNode:
            %(v / 100)
        amount.setInitialValueToResult(result)
        result["_c"] = %"Tint"

    else:
        logi "WARNING: Effect not supported. Layer: ", layer.name
        dumpPropertyTree(p)

proc serializeLayerComponents(layer: Layer): JsonNode =
    result = newJArray()

    let blendMode = layer.blendMode
    if blendMode != BlendingMode.NORMAL:
        result.add(%*{"_c": "VisualModifier", "blendMode": % $blendMode})

    var layerHasRenderableComponents = false
    let effects = layer.propertyGroup("Effects")
    if not effects.isNil:
        for i in 0 ..< effects.numProperties:
            let p = effects.property(i)
            if p.isPropertyGroup and p.canSetEnabled and p.enabled:
                let p = p.toPropertyGroup()
                var renderableComponent = false
                let c = serializeEffect(layer, result.len, p, renderableComponent)
                layerHasRenderableComponents = layerHasRenderableComponents or renderableComponent
                if not c.isNil: result.add(c)

    var source = layer.source
    if not source.isNil:
        if source.jsObjectType == "FootageItem":
            let footageSource = FootageItem(source)
            if not footageSource.file.isNil:
                var imageFiles = if footageSource.duration > 0:
                        getSequenceFilesFromSource(footageSource)
                    else:
                        @[footageSource.file]

                # Paths relative to currently exported composition
                let imageFileRelativeExportPaths = newJArray()

                let footagePath = $footageSource.projectPath
                for i, f in imageFiles:
                    imageFileRelativeExportPaths.add(%getExportPathFromSourceFile(footageSource, f))

                    # Copy the file to the resources
                    if app.settings.getSetting("rodExport", "copyResources") == "true":
                        let resourcePath = gExportFolderPath & footagePath & "/" & $decodeURIComponent(f.name)
                        if not resourcePaths.contains(resourcePath):
                            logi "Copying: ", resourcePath
                            resourcePaths.add(resourcePath)
                            let targetFile = newFile(resourcePath)
                            if not targetFile.parent.create():
                                logi "ERROR: Could not create folder for ", resourcePath
                            if not f.copy(targetFile):
                                logi "ERROR: Could not copy ", resourcePath

                var sprite = newJObject()
                sprite["fileNames"] = imageFileRelativeExportPaths
                sprite["_c"] = %"Sprite"
                result.add(sprite)

            elif layer.isSolidLayer and not layerHasRenderableComponents:
                var solid = newJObject()
                let solidSource = SolidSource(footageSource.mainSource)
                solid["color"] = %* solidSource.color
                solid["size"] = % [source.width, source.height]
                solid["_c"] = % "Solid"
                result.add(solid)

    var text = layer.propertyGroup("Text")
    if not text.isNil:
        var textDoc = text.property("Source Text", TextDocument).value
        var txt = newJObject()
        txt["text"] = % (layer.getText()).replace('\r', '\l')
        txt["font"] = % $textDoc.font
        txt["fontSize"] = % textDoc.fontSize
        txt["color"] = % textDoc.fillColor
        if textDoc.boxText:
            let r = layer.sourceRectAtTime(0, false)
            txt["bounds"] = % [r.left, r.top, r.width, r.height]

        case textDoc.justification
        of tjLeft: txt["justification"] = %"left"
        of tjRight: txt["justification"] = %"right"
        of tjCenter: txt["justification"] = %"center"

        let layerStyles = layer.propertyGroup("Layer Styles")
        let shadow = layerStyles.propertyGroup("Drop Shadow")
        if not shadow.isNil and shadow.canSetEnabled and shadow.enabled:
            let angle = shadow.property("Angle", float32).valueAtTime(0)
            let distance = shadow.property("Distance", float32).valueAtTime(0)
            let color = shadow.property("Color", Vector4).valueAtTime(0)
            let alpha = shadow.property("Opacity", float32).valueAtTime(0) / 100
            txt["shadowColor"] = %[color.x, color.y, color.z, alpha]
            let radAngle = degToRad(angle + 180)
            # txt["shadowOff"] = %[distance * cos(radAngle), - distance * sin(radAngle)]
            txt["shadowX"] = %(distance * cos(radAngle))
            txt["shadowY"] = %(- distance * sin(radAngle))

        let stroke = layerStyles.propertyGroup("Stroke")
        if not stroke.isNil and stroke.canSetEnabled and stroke.enabled:
            let size = stroke.property("Size", float32).valueAtTime(0)
            let color = stroke.property("Color", Vector4).valueAtTime(0)
            let alpha = stroke.property("Opacity", float32).valueAtTime(0) / 100
            txt["strokeColor"] = %[color.x, color.y, color.z, alpha]
            txt["strokeSize"] = %size

        txt["_c"] = %"Text"
        result.add(txt)

proc layerIsCompositionRef(layer: Layer): bool =
    not layer.source.isNil and layer.source.jsObjectType == "CompItem"

proc exportPath(c: Item): string =
    result = c.projectPath
    if result == "/":
        result = "compositions"
    else:
        result = result[1 .. ^1]

proc serializeLayer(layer: Layer): JsonNode =
    result = newJObject()

    logi("LAYER: ", layer.name, ", w: ", layer.width, " h: ", layer.height);
    result["name"] = % layer.mangledName

    let position = addPropDesc(layer, -1, "translation", layer.property("Position", Vector3), newVector3()) do(v: Vector3) -> JsonNode:
        %(newVector3(v.x, v.y, v.z * -1.0))
    position.setInitialValueToResult(result)

    addPropDesc(layer, -1, "tX", layer.property("X Position", float))
    addPropDesc(layer, -1, "tY", layer.property("Y Position", float))

    let scale = addPropDesc(layer, -1, "scale", layer.property("Scale", Vector3), newVector3(100, 100, 100)) do(v: Vector3) -> JsonNode:
        %(v / 100)
    scale.setInitialValueToResult(result)

    if layer.threeDLayer:
        let xprop = layer.property("X Rotation", float)
        let yprop = layer.property("Y Rotation", float)
        let zprop = layer.property("Z Rotation", float)

        let rotationEuler = newPropDescSeparated(layer, -1, "rotation", @[xprop, yprop, zprop]) do(v: seq[float]) -> JsonNode:
            % quaternionWithEulerRotation(newVector3(v[0], v[1], v[2]))
        if not rotationEuler.isNil() and (xprop.isAnimated() or yprop.isAnimated() or zprop.isAnimated()):
            gAnimatedProperties.add(rotationEuler)
        rotationEuler.setInitialValueToResult(result)
    else:
        let rotation = addPropDesc(layer, -1, "rotation", layer.property("Rotation", float), 0) do(v: float) -> JsonNode:
            % quaternionWithZRotation(v)
        rotation.setInitialValueToResult(result)

    let anchor = addPropDesc(layer, -1, "anchor", layer.property("Anchor Point", Vector3), newVector3()) do(v: Vector3) -> JsonNode:
        %v
    anchor.setInitialValueToResult(result)

    let alpha = addPropDesc(layer, -1, "alpha", layer.property("Opacity", float), 100) do(v: float) -> JsonNode:
        %(v / 100.0)
    alpha.setInitialValueToResult(result)

    var children = layer.children
    if children.len > 0:
        var chres = newJArray()
        for child in children:
            if shouldSerializeLayer(child):
                chres.add(serializeLayer(child))

        if chres.len > 0:
            chres.elems.reverse()
            result["children"] = chres

    if layer.layerIsCompositionRef():
        result["compositionRef"] = %relativePathToPath(gCompExportPath, layer.source.exportPath & "/" & $layer.source.name & ".json")

    if not transitiveEffects: result["affectsChildren"] = %false

    var components = serializeLayerComponents(layer)
    if components.len > 0: result["components"] = components

type Marker = object
    time*, duration*: float
    comment*: string
    animation*: string
    loops*: int
    animation_end*: string

proc getMarkers(comp: Composition): seq[Marker] =
    result = @[]

    const undoGroupId = "__rod_export_script_undo_group__"
    app.beginUndoGroup(undoGroupId)
    let tempLayer = comp.layers.addText()

    let tempText = tempLayer.propertyGroup("Text").property("Source Text", TextDocument)
    tempText.expression = "thisComp.marker.numKeys"
    let numMarkers = parseInt($tempText.value.text)

    for i in 1 .. numMarkers:
        tempText.expression = "thisComp.marker.key(" & $i & ").time"
        let markerTime = parseFloat($tempText.value.text)
        tempText.expression = "thisComp.marker.key(" & $i & ").comment"
        let markerComment = $tempText.value.text
        result.add(Marker(
          time: markerTime,
          comment: markerComment
        ))
    app.endUndoGroup()
    app.undo(undoGroupId)

proc parseMarkerComment(comment: string, res: var Marker) =
    for ln in comment.splitLines:
        var kv = ln.split(":")
        if kv.len == 2:
            let k = kv[0].strip()
            let v = kv[1].strip()
            case k
            of "animation": res.animation = v
            of "loops": res.loops = parseInt(v)
            of "animation_end": res.animation_end = v
            else: logi "Unknown marker key: ", k

proc getAnimationEndMarkersFromMarkers(markers: openarray[Marker]): seq[Marker] =
    result = @[]
    for m in markers:
        if m.animation_end.len > 0:
            result.add(m)

proc getAnimationMarkers(comp: Composition): seq[Marker] =
    var markers = getMarkers(comp)
    for i in 0 ..< markers.len:
        parseMarkerComment(markers[i].comment, markers[i])

    var end_markers = getAnimationEndMarkersFromMarkers(markers)

    result = @[]
    for m in markers:
        if m.animation.len == 0:
            logi "WARNING: Marker ignored: ", m.comment
        else:
            result.add(m)

    if result.len > 0:
        for i in 0 ..< result.len - 1:
            result[i].duration = result[i + 1].time - result[i].time

        result[^1].duration = comp.duration - result[^1].time

    for em in end_markers:
        for i in 0 ..< result.len:
            if em.animation_end == result[i].animation:
                doAssert(em.time > result[i].time)
                result[i].duration = em.time - result[i].time

proc `%`(e: KeyframeEase): JsonNode =
    const c = 0.66
    let y = e.speed * (e.influence / 100) * c
    result = %*[
        e.influence / 100,
        y
    ]

proc getPropertyAnimation(pd: PropertyDescription, marker: Marker): JsonNode =
    var animationStartTime = marker.time
    var animationEndTime = marker.time + marker.duration;
    #if (pd.property.numKeys > 0) {
    #  animationStartTime = Math.max(animationStartTime, pd.property.keyTime(1));
    #  animationEndTime = Math.min(animationEndTime, pd.property.keyTime(pd.property.numKeys));
    #}

    #if (animationStartTime >= animationEndTime - 0.0001) {
    # return null;
    #}

    result = newJObject()

    when exportKeyframeAnimations:
        let nk = pd.property.numKeys
        logi "prop: ", pd.fullyQualifiedName
        logi "nk: ", nk
        var keys = newJArray()

        let lastKeyTime = pd.property.keyTime(pd.property.numKeys)

        for i in 1 .. nk:
    #        const c = 0.66
            # let oe = prop.keyOutTemporalEase(i)[0]
            # let outY = oe.speed * (oe.influence / 100) * c
            # let ie = prop.keyInTemporalEase(i)[0]
            # let inY = - ie.speed * (ie.influence / 100) * c
            let inEase = pd.property.keyInTemporalEase(i)
            let outEase = pd.property.keyOutTemporalEase(i)
            if inEase.len != 1 or outEase.len != 1:
                logi "ERROR: Too many eases. Exported file might not be valid."
            let key = %*{
                "ie": inEase[0],
                "oe": outEase[0],
                "p": pd.property.keyTime(i) / lastKeyTime,
                "v": pd.keyValue(i)
            }
            keys.add(key)

            # logi i, " in: ", inY
            # logi i, " out: ", outY
        result["keys"] = keys

    when exportSampledAnimations:
        var fps = 30.0;
        var timeStep = 1.0 / fps;
        var sampledPropertyValues = newJArray()

        var dEndTime = animationEndTime - 0.0001; # Due to floating point errors, we
        # may hit end time, so prevent that.

        var s = animationStartTime
        while s < dEndTime:
            sampledPropertyValues.add(pd.valueAtTime(s))
            s += timeStep
        #  logi(JSON.stringify(sampledPropertyValues));
        #  sampledPropertyValues.push(converter(prop.valueAtTime(animationEndTime, false)));
        result["values"] = sampledPropertyValues

    result["duration"] = %(animationEndTime - animationStartTime)
    if marker.loops != 0: result["numberOfLoops"] = %marker.loops

proc getAnimatableProperties(fromObj: PropertyOwner, res: var seq[AbstractProperty], name: string = "") =
    for i in 0 ..< fromObj.numProperties:
        let p = fromObj.property(i)
        let fullyQualifiedPropName = name & "." & $p.name
        if p.isPropertyGroup:
            if p.name != "Layer Styles" and ((p.isEffect and p.canSetEnabled and p.enabled) or not p.isEffect):
                getAnimatableProperties(p.toPropertyGroup(), res, fullyQualifiedPropName)
        else:
            let pr = p.toAbstractProperty()
            if pr.isTimeVarying and $pr.name notin bannedPropertyNames:
                if not pr.isSeparationLeader or not pr.dimensionsSeparated:
                    logi "Animatable prop: ", fullyQualifiedPropName
                    res.add(pr)

proc layerFootage(layer: Layer): FootageItem =
    var source = layer.source
    if not source.isNil:
        if source.jsObjectType == "FootageItem":
            result = FootageItem(source)

proc isSequenceLayer(layer: Layer): bool =
    let f = layer.layerFootage
    if not f.isNil and not f.file.isNil and f.duration > 0:
        result = true

proc sequenceFrameAtTime(layer: Layer, f: FootageItem, t: float, length: int): int =
    var relTime = t - layer.startTime

    if layer.timeRemapEnabled:
        let timeRemap = layer.property("Time Remap", float)
        relTime = timeRemap.valueAtTime(t)

    # Clamp relTime to layer duration
    if relTime < 0: relTime = 0
    if relTime >= f.duration: relTime = f.duration - 0.01

    result = round(relTime / f.frameDuration mod length.float).int
    if result >= length:
        result.dec()

proc getSequenceLayerAnimationForMarker(layer: Layer, marker: Marker, result: JsonNode) =
    var animationStartTime = marker.time
    var animationEndTime = marker.time + marker.duration;

    var fps = 30.0;
    var timeStep = 1.0 / fps;
    var sampledPropertyValues = newJArray()

    var dEndTime = animationEndTime - 0.0001; # Due to floating point errors, we
    # may hit end time, so prevent that.

    let footage = layer.layerFootage

    var s = animationStartTime
    let length =  getSequenceFilesFromSource(footage).len
    while s < dEndTime:
        sampledPropertyValues.add(%sequenceFrameAtTime(layer, footage, s, length))
        s += timeStep

    let anim = newJObject()
    anim["duration"] = %(animationEndTime - animationStartTime)
    anim["frameLerp"] = %false
    anim["values"] = sampledPropertyValues
    if marker.loops != 0: anim["numberOfLoops"] = %marker.loops

    var fullyQualifiedPropName = layer.mangledName & ".curFrame"
    result[fullyQualifiedPropName] = anim

proc serializeCompositionAnimations(composition: Composition): JsonNode =
    var animationMarkers = getAnimationMarkers(composition)
    result = newJObject()

    for m in animationMarkers:
        var animations = newJObject()
        logi("Exporting animation: ", m.animation, ": ", epochTime())

        for pd in gAnimatedProperties:
            animations[pd.fullyQualifiedName] = getPropertyAnimation(pd, m)

        for layer in composition.layers:
            if shouldSerializeLayer(layer) and layer.isSequenceLayer():
                getSequenceLayerAnimationForMarker(layer, m, animations)

        if animations.len > 0:
            result[m.animation] = animations

proc serializeComposition(composition: Composition): JsonNode =
    layerNames = initTable[int, string]()
    resourcePaths = @[]

    let rootLayer = composition.layer("root")
    if not rootLayer.isNil:
        result = serializeLayer(rootLayer)
        result["name"] = % $composition.name
    else:
        result = % {
          "name": % $composition.name
        }
        var children = newJArray();
        for layer in composition.layers:
            if layer.parent.isNil:
                if shouldSerializeLayer(layer):
                    children.add(serializeLayer(layer))
        children.elems.reverse()
        if children.len > 0:
            result["children"] = children

    let animations = serializeCompositionAnimations(composition)

    if animations.len > 0:
        result["animations"] = animations
    let f = app.project.file
    if not f.isNil:
        result["aep_name"] = % $f.name

proc replacer(n: JsonNode): ref RootObj =
    case n.kind
    of JNull: result = nil
    of JBool:
        let b = n.bval
        {.emit: "`result` = `b`;".}
    of JArray:
        var r = newSeq[ref RootObj]()
        for e in n.elems:
            r.add(replacer(e))
        {.emit: "`result` = `r`;".}
    of JString:
        var e : cstring = n.str
        {.emit: "`result` = `e`;".}
    of JInt:
        let e = n.num
        {.emit: "`result` = `e`;".}
    of JFloat:
        let e = n.fnum
        {.emit: "`result` = `e`;".}
    of JObject:
        {.emit: "`result` = {};"}
        for k, v in n:
            let ck : cstring = k
            let val = replacer(v)
            {.emit: "`result`[`ck`] = `val`;".}

proc fastJsonStringify(n: JsonNode): cstring =
    let r = replacer(n)
    {.emit: "`result` = JSON.stringify(`r`, null, 2);".}

proc exportSelectedCompositions(exportFolderPath: cstring) {.exportc.} =
    logTextField.text = ""

    let compositions = getSelectedCompositions()
    gExportFolderPath = $exportFolderPath
    gAnimatedProperties.setLen(0)
    for c in compositions:
        gCompExportPath = c.exportPath
        let fullExportPath = gExportFolderPath & "/" & gCompExportPath

        try:
            if not newFolder(fullExportPath).create():
                logi "ERROR: Could not create folder ", fullExportPath
        except:
            discard
        let filePath = fullExportPath & "/" & $c.name & ".json"
        logi("Exporting: ", c.name, " to ", filePath)
        let file = newFile(filePath)
        file.encoding = "UTF-8"
        file.openForWriting()
        file.lineFeed = lfUnix
        try:
            let serializedComp = serializeComposition(c)
            serializedComp["version"] = %exportedVersion
            file.write(fastJsonStringify(serializedComp))
        except:
            logi "Exception caught: ", getCurrentExceptionMsg()
            let s = getCurrentException().getStackTrace()
            if not s.isNil: logi s
        file.close()

    logi("Done. ", epochTime())

{.emit: """

function buildUI(contextObj) {
  var mainWindow = null;
  if (contextObj instanceof Panel) {
    mainWindow = contextObj;
  } else {
    mainWindow = new Window("palette", "Animations", undefined, {
      resizeable: true
    });
    mainWindow.size = [640, 300];
  }
  //mainWindow.alignment = ['fill', 'fill'];

  var topGroup = mainWindow.add("group{orientation:'row'}");
  topGroup.alignment = ["fill", "top"];

  var setPathButton = topGroup.add("button", undefined, "Browse");
  setPathButton.alignment = ["left", "center"];

  var filePath = topGroup.add("statictext");
  filePath.alignment = ["fill", "fill"];

  var copyResourcesCheckBox = topGroup.add("checkbox", undefined, "Copy resources");
  copyResourcesCheckBox.alignment = ["right", "center"];
  copyResourcesCheckBox.value = true;
  app.settings.saveSetting("rodExport", "copyResources", "true");

  copyResourcesCheckBox.onClick = function(e) {
    app.settings.saveSetting("rodExport", "copyResources", copyResourcesCheckBox.value + "");
  };

  var transitiveEffectsCheckBox = topGroup.add("checkbox", undefined, "Transitive effects");
  transitiveEffectsCheckBox.alignment = ["right", "center"];
  `transitiveEffects`[0] = app.settings.haveSetting("rodExport", "transitiveEffects") &&
    app.settings.getSetting("rodExport", "transitiveEffects") == "true";
  transitiveEffectsCheckBox.value = `transitiveEffects`[0];

  transitiveEffectsCheckBox.onClick = function(e) {
    `transitiveEffects`[0] = affectsChildrenCheckBox.value;
    app.settings.saveSetting("rodExport", "transitiveEffects", affectsChildrenCheckBox.value + "");
  };

  var exportButton = topGroup.add("button", undefined,
    "Export selected compositions");
  exportButton.alignment = ["right", "center"];
  exportButton.enabled = false;

  if (app.settings.haveSetting("rodExport", "outputPath")) {
    exportButton.enabled = true;
    filePath.text = app.settings.getSetting("rodExport", "outputPath");
  } else {
    filePath.text = "Output: (not specified)";
  }

  var resultText = mainWindow.add(
    "edittext{alignment:['fill','fill'], properties: { multiline:true } }");
  `logTextField`[0] = resultText;

  setPathButton.onClick = function(e) {
    var outputFile = Folder.selectDialog("Choose an output folder");
    if (outputFile) {
      exportButton.enabled = true;
      filePath.text = outputFile.absoluteURI;
      app.settings.saveSetting("rodExport", "outputPath", outputFile.absoluteURI);
    } else {
      exportButton.enabled = false;
    }
  };

  exportButton.onClick = function(e) {
    exportSelectedCompositions(filePath.text);
  };

  mainWindow.addEventListener("resize", function(e) {
    this.layout.resize();
  });

  mainWindow.addEventListener("close", function(e) {
    app.cancelTask(taskId);
    stopServer();
  });

  mainWindow.onResizing = mainWindow.onResize = function() {
    this.layout.resize();
  };

  if (mainWindow instanceof Window) {
    //    mainWindow.onShow = function() {
    //        readMetaData();
    //    }
    mainWindow.show();
  } else {
    mainWindow.layout.layout(true);
    //    readMetaData();
  }
}

buildUI(this);

""".}
