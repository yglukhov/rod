
type
    Application* = ref ApplicationObj
    ApplicationObj {.importc.} = object of RootObj
        project*: Project

    Project* = ref ProjectObj
    ProjectObj {.importc.} = object of RootObj
        selection*: seq[Item]

    ColorLabel* = range[0 .. 16]

    Item* = ref ItemObj
    ItemObj {.importc.} = object of RootObj
        id*: int
        typeName*: cstring
        selected*: bool
        name*: cstring
        comment*: cstring
        color*: ColorLabel
        parentFolder*: FolderItem

    AVItem* = ref AVItemObj
    AVItemObj {.importc.} = object of ItemObj
        duration*: float

    Composition* = ref CompositionObj
    CompositionObj {.importc.} = object of AVItemObj

    Collection*[T] = ref object of RootObj
        fieldToCheckType: T

    FolderItem* = ref FolderItemObj
    FolderItemObj {.importc.} = object of ItemObj

    File* = ref FileObj
    FileObj {.importc.} = object of RootObj
        name*: cstring
        path*: cstring

    Folder* = ref FolderObj
    FolderObj {.importc.} = object of RootObj
        name*: cstring

    Layer* = ref LayerObj
    LayerObj {.importc.} = object of ItemObj
        numProperties*: int
        containingComp*: Composition
        parent*: Layer
        enabled*: bool
        width*, height*: int
        source*: Item

    TextLayer* = ref TextLayerObj
    TextLayerObj {.importc.} = object of LayerObj

    PropertyBase* = ref PropertyBaseObj
    PropertyBaseObj {.importc.} = object of RootObj
        name*: cstring

    PropertyType* = enum
        ptProperty
        ptIndexedGroup
        ptNamedGroup

    PropertyValueType* = enum
        pvtVoid, pvtColor, pvtCustomValue, pvtLayerIndex, pvtMaskIndex,
        pvtMarker, pvtShape, pvtTextDocument,
        pvt1d, pvt2d, pvt2dSpatial, pvt3d, pvt3dSpatial

    AbstractProperty* = ref AbstractPropertyObj
    AbstractPropertyObj = object of PropertyBaseObj
        expression*: cstring
        expressionEnabled*: bool
        isTimeVarying*: bool
        dimensionsSeparated*: bool
        isSeparationLeader*: bool

    Property*[T] = ref PropertyObj[T]
    PropertyObj[T] = object of AbstractPropertyObj
        thisFieldIsNeededOnlyToSuppressNimWarning: T

    PropertyGroup* = ref PropertyGroupObj
    PropertyGroupObj = object of PropertyBaseObj

    EditText* = ref EditTextObj
    EditTextObj {.importc.} = object of RootObj
        text*: cstring

proc newFile*(path: cstring): File {.importc: "new File".}
proc open*(f: File, mode: cstring) {.importcpp.}
template openForWriting*(f: File) = f.open("w")
proc write*(f: File, content: cstring) {.importcpp.}
proc close*(f: File) {.importcpp.}

proc newFolder*(path: cstring): Folder {.importc: "new Folder".}
proc getFiles*(f: Folder): seq[File] {.importcpp.}

template `[]`*[T](c: Collection[T], i: int): T = cast[seq[type(c.fieldToCheckType)]](c)[i + 1]
template len*[T](c: Collection[T]): int = cast[seq[T]](c).len

proc remove*(i: Item) {.importcpp.}

proc layers*(c: Composition): Collection[Layer] = {.emit:"`result` = `c`.layers;".}
proc layer*(c: Composition, name: cstring): Layer {.importcpp.}

iterator items*[T](c: Collection[T]): T =
    for i in 0 ..< c.len: yield c[i]

proc propertyType*(p: PropertyBase): PropertyType =
    {.emit: """
    switch(`p`.propertyType) {
        case PropertyType.PROPERTY: `result` = 0; break;
        case PropertyType.INDEXED_GROUP: `result` = 1; break;
        case PropertyType.NAMED_GROUP: `result` = 2; break;
    }
    """.}

proc propertyValueType*(p: AbstractProperty): PropertyValueType =
    {.emit: """
    switch(`p`.propertyValueType) {
        case PropertyValueType.NO_VALUE: `result` = 0; break;
        case PropertyValueType.COLOR: `result` = 1; break;
        case PropertyValueType.CUSTOM_VALUE: `result` = 2; break;
        case PropertyValueType.LAYER_INDEX: `result` = 3; break;
        case PropertyValueType.MASK_INDEX: `result` = 4; break;
        case PropertyValueType.MARKER: `result` = 5; break;
        case PropertyValueType.SHAPE: `result` = 6; break;
        case PropertyValueType.TEXT_DOCUMENT: `result` = 7; break;
        case PropertyValueType.OneD: `result` = 8; break;
        case PropertyValueType.TwoD: `result` = 9; break;
        case PropertyValueType.TwoD_SPATIAL: `result` = 10; break;
        case PropertyValueType.ThreeD: `result` = 11; break;
        case PropertyValueType.ThreeD_SPATIAL: `result` = 12; break;
    }
    """.}

template valueTypeFromType(t: typedesc[array[2, float32]]): expr = [pvt2d, pvt2dSpatial]
template valueTypeFromType(t: typedesc[array[3, float32]]): expr = [pvt3d, pvt3dSpatial]
template valueTypeFromType(t: typedesc[float32]): expr = [pvt1d]
template valueTypeFromType(t: typedesc[float]): expr = [pvt1d]
template valueTypeFromType(t: typedesc[cstring]): expr = [pvt1d]

template isPropertyGroup*(p: PropertyBase): bool = p.propertyType != ptProperty

proc toAbstractProperty*(p: PropertyBase): AbstractProperty =
    if p.isPropertyGroup:
        raise newException(Exception, "Property is a group")
    result = cast[AbstractProperty](p)

proc checkPropType(p: AbstractProperty, rt: openarray[PropertyValueType]) =
    let pt = p.propertyValueType
    if pt notin rt:
        raise newException(Exception, "Property " & $p.name & " requested type " & ($ @rt) & " but actual type is " & $pt)

proc toPropertyOfType*(p: PropertyBase, T: typedesc): Property[T] =
    p.toAbstractProperty().checkPropType(valueTypeFromType(T))
    result = cast[Property[T]](p)

proc toPropertyOfType*(p: AbstractProperty, T: typedesc): Property[T] =
    p.checkPropType(valueTypeFromType(T))
    result = cast[Property[T]](p)

proc toPropertyGroup*(p: PropertyBase): PropertyGroup =
    if not p.isPropertyGroup:
        raise newException(Exception, "Property is not a group")
    result = cast[PropertyGroup](p)

proc property*(layer: Layer, name: cstring): PropertyBase {.importcpp.}
proc indexedProperty(layer: Layer, i: int): PropertyBase {.importcpp: "property".}

proc property*(prop: PropertyGroup, name: cstring): PropertyBase {.importcpp.}
proc indexedProperty(prop: PropertyGroup, i: int): PropertyBase {.importcpp: "property".}

type PropertyOwner* = Layer or PropertyGroup

template property*(owner: PropertyOwner, i: int): PropertyBase = owner.indexedProperty(i + 1)

template propertyGroup*(owner: PropertyOwner, name: cstring): PropertyGroup =
    owner.property(name).toPropertyGroup()

proc property*(owner: PropertyOwner, name: cstring, T: typedesc): Property[T] =
    toPropertyOfType(owner.property(name), T)
proc property*(owner: PropertyOwner, i: int, T: typedesc): Property[T] =
    toPropertyOfType(owner.property(i), T)

proc numProperties*(owner: PropertyOwner): int {.importcpp.}

proc value*[T](p: Property[T]): T = {.emit: "`result` = `p`.value;".}
proc valueAtTime*[T](p: Property[T], t: float, e: bool = false): T =
    {.emit: "`result` = `p`.valueAtTime(`t`, `e`);".}

proc children*(layer: Layer): seq[Layer] =
    result = newSeq[Layer]()
    for i in layer.containingComp.layers:
        if i.parent == layer: result.add(i)

proc addText*(col: Collection[Layer], text: cstring): TextLayer {.importcpp.}

var app* {.importc, nodecl.}: Application
