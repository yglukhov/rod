import nimx.types
import nimx.matrixes

import rod.rod_types
import rod.component
import rod.viewport
import rod.node
import rod.property_visitor

export LightSource

proc `lightAmbient=`*(ls: LightSource, val: Coord) =
    ls.mLightAmbient = val
    ls.lightAmbientInited = true
proc `lightDiffuse=`*(ls: LightSource, val: Coord) =
    ls.mLightDiffuse = val
    ls.lightDiffuseInited = true
proc `lightSpecular=`*(ls: LightSource, val: Coord) =
    ls.mLightSpecular = val
    ls.lightSpecularInited = true
proc `lightConstant=`*(ls: LightSource, val: Coord) =
    ls.mLightConstant = val
    ls.lightConstantInited = true
proc `lightLinear=`*(ls: LightSource, val: Coord) =
    ls.mLightLinear = val
    ls.lightLinearInited = true
proc `lightQuadratic=`*(ls: LightSource, val: Coord) =
    ls.mLightQuadratic = val
    ls.lightQuadraticInited = true
proc `lightAttenuation=`*(ls: LightSource, val: Coord) =
    ls.mLightAttenuation = val
    ls.lightAttenuationInited = true

template lightAmbient*(ls: LightSource): Coord = ls.mLightAmbient
template lightDiffuse*(ls: LightSource): Coord = ls.mLightDiffuse
template lightSpecular*(ls: LightSource): Coord = ls.mLightSpecular
template lightConstant*(ls: LightSource): Coord = ls.mLightConstant
template lightLinear*(ls: LightSource): Coord = ls.mLightLinear
template lightQuadratic*(ls: LightSource): Coord = ls.mLightQuadratic
template lightAttenuation*(ls: LightSource): Coord = ls.mLightAttenuation

proc setDefaultLightSource*(ls: LightSource) =
    ls.lightAmbient = 1.0
    ls.lightDiffuse = 1.0
    ls.lightSpecular = 1.0
    ls.lightConstant = 1.0
    ls.lightLinear = 0.000014
    ls.lightQuadratic = 0.00000007
    ls.lightAttenuationInited = false

method init*(ls: LightSource) =
    procCall ls.Component.init()
    ls.setDefaultLightSource()

method componentNodeWasAddedToSceneView*(ls: LightSource) =
    ls.node.sceneView.addLightSource(ls)

method componentNodeWillBeRemovedFromSceneView(ls: LightSource) =
    ls.node.sceneView.removeLightSource(ls)

method visitProperties*(ls: LightSource, p: var PropertyVisitor) =
    p.visitProperty("ambient", ls.lightAmbient)
    p.visitProperty("diffuse", ls.lightDiffuse)
    p.visitProperty("specular", ls.lightSpecular)
    p.visitProperty("constant", ls.lightConstant)
    # p.visitProperty("linear", ls.lightLinear)
    # p.visitProperty("quadratic", ls.lightQuadratic)

registerComponent[LightSource]()
