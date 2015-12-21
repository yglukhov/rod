import nimx.types
import nimx.matrixes

import rod.rod_types
import rod.component
import rod.viewport

export LightSource

proc `lightAmbient=`*(l: LightSource, val: Coord) = 
    l.lightAmbient = val
    l.lightAmbientInited = true
proc `lightDiffuse=`*(l: LightSource, val: Coord) = 
    l.lightDiffuse = val
    l.lightDiffuseInited = true
proc `lightSpecular=`*(l: LightSource, val: Coord) = 
    l.lightSpecular = val
    l.lightSpecularInited = true
proc `lightConstant=`*(l: LightSource, val: Coord) = 
    l.lightConstant = val
    l.lightConstantInited = true
proc `lightLinear=`*(l: LightSource, val: Coord) = 
    l.lightLinear = val
    l.lightLinearInited = true
proc `lightQuadratic=`*(l: LightSource, val: Coord) = 
    l.lightQuadratic = val
    l.lightQuadraticInited = true
proc `lightAttenuation=`*(l: LightSource, val: Coord) = 
    l.lightAttenuation = val
    l.lightAttenuationInited = true

template lightAmbient*(l: LightSource): Coord = 
    result = l.lightAmbient
template lightDiffuse*(l: LightSource): Coord = 
    result = l.lightDiffuse
template lightSpecular*(l: LightSource): Coord = 
    result = l.lightSpecular
template lightConstant*(l: LightSource): Coord = 
    result = l.lightConstant
template lightLinear*(l: LightSource): Coord = 
    result = l.lightLinear
template lightQuadratic*(l: LightSource): Coord = 
    result = l.lightQuadratic
template lightAttenuation*(l: LightSource): Coord = 
    result = l.lightAttenuation

proc setDefaultLightSource*(l: LightSource) = 
    l.lightAmbient = 0.7
    l.lightDiffuse = 0.8
    l.lightSpecular = 0.9
    l.lightConstant = 1.0
    l.lightLinear = 0.000014
    l.lightQuadratic = 0.00000007
    l.lightAttenuationInited = false

method componentNodeWasAddedToViewport*(l: LightSource) = 
    l.node.mViewport.addLightSource(l)

method componentNodeWillBeRemovedFromViewport*(l: LightSource) =
    l.node.mViewport.removeLightSource(l)

registerComponent[LightSource]()
