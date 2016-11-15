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

const useObsoleteNullLayerCheck = false # Flip this if you have problems with exporting null layers

proc getObjectsWithTypeFromCollection*(t: typedesc, collection: openarray[Item], typeName: string): seq[t] =
    for i in collection:
        if i.jsObjectType == typeName:
            result.add(cast[t](i))

proc getSelectedCompositions(): seq[Composition] =
    getObjectsWithTypeFromCollection(Composition, app.project.selection, "CompItem")

var logTextField: EditText

proc appendToJSStringAux(s: cstring, a: cstring) {.importcpp: "# += #".}
template `&=`(s: var cstring, a: cstring) = appendToJSStringAux(s, a)

proc logi(args: varargs[string, `$`]) =
    for i in args:
        logTextField.text &= i
    logTextField.text &= "\n"

proc shouldSerializeLayer(layer: Layer): bool = return layer.enabled

template quaternionWithZRotation(zAngle: float32): Quaternion = newQuaternion(zAngle, newVector3(0, 0, 1))

var propertyNameMap = {
    "Rotation" : "rotation",
    "Position" : "translation",
    "X Position": "tX",
    "Y Position": "tY",
    "Scale": "scale",
    "Opacity": "alpha",
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

let bannedPropertyNames = ["Time Remap", "Marker", "Checkbox", "Value/Offset/Random Max", "Slider", "Source Text"]

var gCompExportPath = ""
var gExportFolderPath = ""

var layerNames = initTable[int, string]()
var resourcePaths: seq[string] = @[]

proc getExportPathFromSourceFile(footageSource: FootageItem, file: File): string =
    var path = $footageSource.projectPath
    if path[^1] != '/': path &= "/"
    result = relativePathToPath("/" & gCompExportPath, path & $decodeURIComponent(file.name))

proc `%`[T: string | SomeNumber](s: openarray[T]): JsonNode =
    result = newJArray()
    for c in s: result.add(%c)

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
    let textMarker = layer.property("Marker", MarkerValue).valueAtTime(0.0, false).comment
    let textLayer = layer.propertyGroup("Text").property("Source Text", TextDocument).value.text

    if textMarker == textLayer or removeTextAttributes($textMarker) == textLayer:
        return true

proc getText(layer: Layer): string =
    let markerText = layer.property("Marker", MarkerValue).valueAtTime(0.0, false).comment
    let text = layer.propertyGroup("Text")
    let str = text.property("Source Text", TextDocument).value.text

    if not text.isNil:
        if markerText == "":
            return $str
    if layer.isTextMarkerValid():
        result = $markerText
    else:
        raise newException(Exception, "Marker is not valid for text: " & $str)

proc serializeLayerComponents(layer: Layer): JsonNode =
    result = newJObject()
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
                result["Sprite"] = sprite
            elif layer.isSolidLayer:
                var solid = newJObject()
                let solidSource = SolidSource(footageSource.mainSource)
                solid["color"] = %* solidSource.color
                solid["size"] = % [source.width, source.height]
                result["Solid"] = solid


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


    let effects = layer.propertyGroup("Effects")
    if not effects.isNil:
        let levels = effects.propertyGroup("Levels (Individual Controls)")
        if not levels.isNil:
            var lvl = levelsValueAtTime(levels, 0)
            result["ChannelLevels"] = lvl

        let numbers = effects.propertyGroup("Numbers")
        if not numbers.isNil:
            var txt = newJObject()
            var color = numbers.property("Fill Color", Vector4).valueAtTime(0)
            txt["color"] = %color
            txt["fontSize"] = % numbers.property("Size", float).valueAtTime(0)
            result["Text"] = txt
            result.delete("Solid")

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

        let shadow = layer.propertyGroup("Layer Styles").propertyGroup("Drop Shadow")
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

        let stroke = layer.propertyGroup("Layer Styles").propertyGroup("Stroke")
        if not stroke.isNil and stroke.canSetEnabled and stroke.enabled:
            let size = stroke.property("Size", float32).valueAtTime(0)
            let color = stroke.property("Color", Vector4).valueAtTime(0)
            let alpha = stroke.property("Opacity", float32).valueAtTime(0) / 100
            txt["strokeColor"] = %[color.x, color.y, color.z, alpha]
            txt["strokeSize"] = %size

        result["Text"] = txt

proc layerIsCompositionRef(layer: Layer): bool =
    not layer.source.isNil and layer.source.jsObjectType == "CompItem"

proc requiresAuxParent(layer: Layer): bool =
    let ap = layer.property("Anchor Point", Vector3)
    if ap.value != newVector3(0, 0, 0):
        result = true
    if layer.blendMode != BlendingMode.NORMAL:
        result = true

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

proc auxLayerName(layer: Layer): string = layer.mangledName & "$AUX"

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
    result["translation"] = % layer.property("Position", Vector3).valueAtTime(0)
    var scale = layer.property("Scale", Vector3).valueAtTime(0)
    if scale != newVector3(100, 100, 100):
        scale /= 100
        result["scale"] = %scale
    var rotation = layer.property("Rotation", float32).valueAtTime(0, false);
    if (rotation != 0):
        result["rotation"] = % quaternionWithZRotation(rotation)

    let opacity = layer.property("Opacity", float).valueAtTime(0)
    if opacity != 100:
        result["alpha"] = % (opacity / 100.0)

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

    var components = serializeLayerComponents(layer)
    if components.len > 0: result["components"] = components

    if layer.requiresAuxParent:
        logi "Creating aux parent for: ", layer.mangledName
        var auxNode = newJObject()
        auxNode["name"] = % layer.auxLayerName
        let pos = layer.property("Position", Vector3).valueAtTime(0)
        auxNode["translation"] = % pos
        if not result{"scale"}.isNil:
            auxNode["scale"] = result["scale"]
            result.delete("scale")

        if not result{"rotation"}.isNil:
            auxNode["rotation"] = result["rotation"]
            result.delete("rotation")

        result["translation"] = % (- layer.property("Anchor Point", Vector3).valueAtTime(0))
        auxNode["children"] = % [result]

        let blendMode = layer.blendMode
        if blendMode != BlendingMode.NORMAL:
            auxNode["components"] = %*{"VisualModifier": {"blendMode": % $blendMode}}

        result = auxNode

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

proc jsonPropertyKeyValueAccessor(p: AbstractProperty): proc(k: int): JsonNode =
    case $p.name
    of "Rotation":
        let cp = p.toPropertyOfType(float)
        result = proc(k: int): JsonNode =
            % quaternionWithZRotation(cp.keyValue(k))
    of "Scale":
        let cp = p.toPropertyOfType(Vector3)
        result = proc(k: int): JsonNode =
            % (cp.keyValue(k) / 100)
    of "Opacity":
        let cp = p.toPropertyOfType(float)
        result = proc(k: int): JsonNode =
            % (cp.keyValue(k) / 100)
    else:
        case p.propertyValueType
        of pvt2d, pvt2dSpatial:
            let cp = p.toPropertyOfType(Vector2)
            result = proc(k: int): JsonNode =
                % (cp.keyValue(k))

        of pvt3d, pvt3dSpatial:
            let cp = p.toPropertyOfType(Vector3)
            result = proc(k: int): JsonNode =
                % (cp.keyValue(k))

        of pvt1d:
            let cp = p.toPropertyOfType(float)
            result = proc(k: int): JsonNode =
                % (cp.keyValue(k))
        else:
            raise newException(Exception, "Unknown property type to convert: " & $p.propertyValueType)

proc jsonPropertyAccessor(p: AbstractProperty): proc(t: float): JsonNode =
    case $p.name
    of "Rotation":
        let cp = p.toPropertyOfType(float)
        result = proc(t: float): JsonNode =
            % quaternionWithZRotation(cp.valueAtTime(t))
    of "Scale":
        let cp = p.toPropertyOfType(Vector3)
        result = proc(t: float): JsonNode =
            % (cp.valueAtTime(t) / 100)
    of "Opacity":
        let cp = p.toPropertyOfType(float)
        result = proc(t: float): JsonNode =
            % (cp.valueAtTime(t) / 100)
    else:
        case p.propertyValueType
        of pvt2d, pvt2dSpatial:
            let cp = p.toPropertyOfType(Vector2)
            result = proc(t: float): JsonNode =
                % (cp.valueAtTime(t))

        of pvt3d, pvt3dSpatial:
            let cp = p.toPropertyOfType(Vector3)
            result = proc(t: float): JsonNode =
                % (cp.valueAtTime(t))

        of pvt1d:
            let cp = p.toPropertyOfType(float)
            result = proc(t: float): JsonNode =
                % (cp.valueAtTime(t))

        else:
            raise newException(Exception, "Unknown property type to convert: " & $p.propertyValueType)

proc `%`(e: KeyframeEase): JsonNode =
    const c = 0.66
    let y = e.speed * (e.influence / 100) * c
    result = %*[
        e.influence / 100,
        y
    ]

proc getPropertyAnimation(prop: AbstractProperty, marker: Marker): JsonNode =
    var animationStartTime = marker.time
    var animationEndTime = marker.time + marker.duration;
    #if (prop.numKeys > 0) {
    #  animationStartTime = Math.max(animationStartTime, prop.keyTime(1));
    #  animationEndTime = Math.min(animationEndTime, prop.keyTime(prop.numKeys));
    #}

    #if (animationStartTime >= animationEndTime - 0.0001) {
    # return null;
    #}

    result = newJObject()

    when exportKeyframeAnimations:
        let nk = prop.numKeys
        logi "prop: ", prop.name
        logi "nk: ", nk
        var keys = newJArray()

        let lastKeyTime = prop.keyTime(prop.numKeys)

        let keyValueAccessor = jsonPropertyKeyValueAccessor(prop)

        for i in 1 .. nk:
    #        const c = 0.66
            # let oe = prop.keyOutTemporalEase(i)[0]
            # let outY = oe.speed * (oe.influence / 100) * c
            # let ie = prop.keyInTemporalEase(i)[0]
            # let inY = - ie.speed * (ie.influence / 100) * c
            let inEase = prop.keyInTemporalEase(i)
            let outEase = prop.keyOutTemporalEase(i)
            if inEase.len != 1 or outEase.len != 1:
                logi "ERROR: Too many eases. Exported file might not be valid."
            let key = %*{
                "ie": inEase[0],
                "oe": outEase[0],
                "p": prop.keyTime(i) / lastKeyTime,
                "v": keyValueAccessor(i)
            }
            keys.add(key)

            # logi i, " in: ", inY
            # logi i, " out: ", outY
        result["keys"] = keys

    when exportSampledAnimations:
        var fps = 30.0;
        var timeStep = 1.0 / fps;
        var sampledPropertyValues = newJArray()
        var accessor = jsonPropertyAccessor(prop)

        var dEndTime = animationEndTime - 0.0001; # Due to floating point errors, we
        # may hit end time, so prevent that.

        var s = animationStartTime
        while s < dEndTime:
            sampledPropertyValues.add(accessor(s))
            s += timeStep
        #  logi(JSON.stringify(sampledPropertyValues));
        #  sampledPropertyValues.push(converter(prop.valueAtTime(animationEndTime, false)));
        result["values"] = sampledPropertyValues

    result["duration"] = %(animationEndTime - animationStartTime)
    if marker.loops != 0: result["numberOfLoops"] = %marker.loops

proc mapPropertyName(name: string): string =
    result = propertyNameMap.getOrDefault(name)
    if result.len == 0:
        result = name

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

proc belongsToAux(p: AbstractProperty): bool =
    for i in ["Scale".cstring, "Rotation", "Position", "X Position", "Y Position"]:
        if p.name == i: return true

proc getLayerAnimationForMarker(layer: Layer, marker: Marker, props: openarray[AbstractProperty], result: JsonNode) =
    for pr in props:
        var anim = getPropertyAnimation(pr, marker)
        let layerName = if pr.belongsToAux and layer.requiresAuxParent:
                layer.auxLayerName
            else:
                layer.mangledName
        var fullyQualifiedPropName = layerName & "." & mapPropertyName($pr.name)
        result[fullyQualifiedPropName] = anim

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

    var layerAnimatebleProps = newSeq[seq[AbstractProperty]]()

    for m in animationMarkers:
        var animations = newJObject()
        logi("Exporting animation: ", m.animation, ": ", epochTime())
        var i = 0
        for layer in composition.layers:
            if shouldSerializeLayer(layer):
                if layerAnimatebleProps.len <= i:
                    var props = newSeq[AbstractProperty]()
                    getAnimatableProperties(layer, props)
                    layerAnimatebleProps.add(props)
                getLayerAnimationForMarker(layer, m, layerAnimatebleProps[i], animations)

                if layer.isSequenceLayer():
                    getSequenceLayerAnimationForMarker(layer, m, animations)

                inc i
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
    result["aep_name"] = % $app.project.file.name

proc replacer(n: JsonNode): ref RootObj {.exportc.} =
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
    {.emit: "`result` = JSON.stringify(`replacer`(`n`), null, 2);".}

proc exportSelectedCompositions(exportFolderPath: cstring) {.exportc.} =
    let compositions = getSelectedCompositions()
    gExportFolderPath = $exportFolderPath
    for c in compositions:
        gCompExportPath = c.exportPath
        let fullExportPath = gExportFolderPath & "/" & gCompExportPath
        if not newFolder(fullExportPath).create():
            logi "ERROR: Could not create folder ", fullExportPath
        let filePath = fullExportPath & "/" & $c.name & ".json"
        logi("Exporting: ", c.name, " to ", filePath)
        let file = newFile(filePath)
        file.encoding = "UTF-8"
        file.openForWriting()
        file.lineFeed = lfUnix
        try:
            var serializedComp = serializeComposition(c)
            file.write(fastJsonStringify(serializedComp))
        except:
            logi("Exception caught: ", getCurrentExceptionMsg())
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

  var isCopyResources = topGroup.add("checkbox", undefined, "Copy resources");
  isCopyResources.alignment = ["right", "center"];
  isCopyResources.value = true
  app.settings.saveSetting("rodExport", "copyResources", "true")

  isCopyResources.onClick = function(e) {
    app.settings.saveSetting("rodExport", "copyResources", isCopyResources.value + "");
  }

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
    `logTextField`[0].text = "";
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
