import nimx.types
import nimx.matrixes

import rod.component

type LightSource* = ref object of Component
    lightPosition: Vector4 
    
    lightAmbient: float32
    lightDiffuse: float32
    lightSpecular: float32
    lightConstant: float32
    lightLinear: float32
    lightQuadratic: float32
    lightAttenuation: float32
    
    lightPosInited*: bool
    lightAmbientInited*: bool
    lightDiffuseInited*: bool
    lightSpecularInited*: bool
    lightConstantInited*: bool
    lightLinearInited*: bool
    lightQuadraticInited*: bool
    lightAttenuationInited*: bool

proc setPosition*(l: LightSource, x, y, z, w: Coord = 0) = 
    l.lightPosition = newVector4(x, y, z, w)
    l.lightPosInited = true
proc setAmbient*(l: LightSource, val: Coord) = 
    l.lightAmbient = val
    l.lightAmbientInited = true
proc setDiffuse*(l: LightSource, val: Coord) = 
    l.lightDiffuse = val
    l.lightDiffuseInited = true
proc setSpecular*(l: LightSource, val: Coord) = 
    l.lightSpecular = val
    l.lightSpecularInited = true
proc setConstant*(l: LightSource, val: Coord) = 
    l.lightConstant = val
    l.lightConstantInited = true
proc setLinear*(l: LightSource, val: Coord) = 
    l.lightLinear = val
    l.lightLinearInited = true
proc setQuadratic*(l: LightSource, val: Coord) = 
    l.lightQuadratic = val
    l.lightQuadraticInited = true
proc setAttenuation*(l: LightSource, val: Coord) = 
    l.lightAttenuation = val
    l.lightAttenuationInited = true

proc getPosition*(l: LightSource): Vector4 = 
    result = l.lightPosition
proc getAmbient*(l: LightSource): Coord = 
    result = l.lightAmbient
proc getDiffuse*(l: LightSource): Coord = 
    result = l.lightDiffuse
proc getSpecular*(l: LightSource): Coord = 
    result = l.lightSpecular
proc getConstant*(l: LightSource): Coord = 
    result = l.lightConstant
proc getLinear*(l: LightSource): Coord = 
    result = l.lightLinear
proc getQuadratic*(l: LightSource): Coord = 
    result = l.lightQuadratic
proc getAttenuation*(l: LightSource): Coord = 
    result = l.lightAttenuation

proc setDefaultLightSourceWithPosition*(l: LightSource, x, y, z, w: Coord = 0) = 
    l.setPosition(x, y, z, w)
    l.setAmbient(0.7)
    l.setDiffuse(0.8)
    l.setSpecular(0.9)
    l.setConstant(1.0)
    l.setLinear(0.000014)
    l.setQuadratic(0.00000007)

    l.lightAttenuationInited = false

proc newDefaultLightSourceWithPosition*(x, y, z, w: Coord = 0): LightSource = 
    result.new()
    result.setDefaultLightSourceWithPosition(x, y, z, w)

method init*(l: LightSource) =
    l.setDefaultLightSourceWithPosition(0.0, 0.0, 0.0, 0.0)
    procCall l.Component.init()

method draw*(l: LightSource) = 
    l.setPosition(l.node.translation.x, l.node.translation.y, l.node.translation.z, l.lightPosition.w)
    # l.setAmbient(l.node.scale.x)
    # l.setDiffuse(l.node.scale.y)
    # l.setSpecular(l.node.scale.z)

# method componentNodeWasAddedToViewport*(c: Component) {.base.} = discard
# method componentNodeWillBeRemovedFromViewport*(c: Component) {.base.} = discard

registerComponent[LightSource]()
