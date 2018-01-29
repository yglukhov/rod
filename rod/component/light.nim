import json
import nimx.types
import nimx.matrixes
import nimx.property_visitor

import rod.rod_types
import rod.component
import rod.viewport
import rod.node
import rod.tools.serializer

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
proc `lightAttenuationInited=`*(ls: LightSource, val: bool) =
    ls.mLightAttenuationInited = val
    if ls.mLightAttenuationInited:
        ls.lightConstantInited = false
        ls.lightLinearInited = false
        ls.lightQuadraticInited = false
    else:
        ls.lightConstantInited = true
        ls.lightLinearInited = true
        ls.lightQuadraticInited = true
proc `lightAttenuation=`*(ls: LightSource, val: Coord) =
    ls.mLightAttenuation = val
proc `lightColor=`*(ls: LightSource, val: Color) =
    ls.mLightColor = val

template lightAmbient*(ls: LightSource): Coord = ls.mLightAmbient
template lightDiffuse*(ls: LightSource): Coord = ls.mLightDiffuse
template lightSpecular*(ls: LightSource): Coord = ls.mLightSpecular
template lightConstant*(ls: LightSource): Coord = ls.mLightConstant
template lightLinear*(ls: LightSource): Coord = ls.mLightLinear
template lightQuadratic*(ls: LightSource): Coord = ls.mLightQuadratic
template lightAttenuation*(ls: LightSource): Coord = ls.mLightAttenuation
template lightAttenuationInited*(ls: LightSource): bool = ls.mLightAttenuationInited
template lightColor*(ls: LightSource): Color = ls.mLightColor

proc setDefaultLightSource*(ls: LightSource) =
    ls.lightAmbient = 1.0
    ls.lightDiffuse = 1.0
    ls.lightSpecular = 1.0
    ls.lightConstant = 1.0
    ls.lightLinear = 0.000014
    ls.lightQuadratic = 0.00000007
    # ls.lightAttenuationInited = false
    ls.lightColor = newColor(1.0, 1.0, 1.0, 1.0)
    ls.lightAttenuation = 1.0
    ls.lightAttenuationInited = true

method init*(ls: LightSource) =
    procCall ls.Component.init()
    ls.setDefaultLightSource()

method componentNodeWasAddedToSceneView*(ls: LightSource) =
    ls.node.sceneView.addLightSource(ls)

method componentNodeWillBeRemovedFromSceneView(ls: LightSource) =
    ls.node.sceneView.removeLightSource(ls)

method getBBox*(ls: LightSource): BBox =
    result.minPoint = newVector3(-3, -3, -3)
    result.maxPoint = newVector3(3, 3, 3)

method deserialize*(ls: LightSource, j: JsonNode, s: Serializer) =
    var v = j{"ambient"}
    if not v.isNil:
        ls.lightAmbient = v.getFloat()

    v = j{"diffuse"}
    if not v.isNil:
        ls.lightDiffuse = v.getFloat()

    v = j{"specular"}
    if not v.isNil:
        ls.lightSpecular = v.getFloat()

    v = j{"constant"}
    if not v.isNil:
        ls.lightConstant = v.getFloat()

    v = j{"linear"}
    if not v.isNil:
        ls.lightLinear = v.getFloat()

    v = j{"quadratic"}
    if not v.isNil:
        ls.lightQuadratic = v.getFloat()

    v = j{"is_precomp_attenuation"}
    if not v.isNil:
        ls.lightAttenuationInited = v.getBool()

    v = j{"attenuation"}
    if not v.isNil:
        ls.lightAttenuation = v.getFloat()

    v = j{"color"}
    if not v.isNil:
        ls.lightColor.r = v[0].getFloat()
        ls.lightColor.g = v[1].getFloat()
        ls.lightColor.b = v[2].getFloat()
        ls.lightColor.a = v[3].getFloat()

method serialize*(c: LightSource, s: Serializer): JsonNode =
    result = newJObject()
    result.add("ambient", s.getValue(c.lightAmbient))
    result.add("diffuse", s.getValue(c.lightDiffuse))
    result.add("specular", s.getValue(c.lightSpecular))
    result.add("constant", s.getValue(c.lightConstant))
    result.add("linear", s.getValue(c.lightLinear))
    result.add("quadratic", s.getValue(c.lightQuadratic))
    result.add("is_precomp_attenuation", s.getValue(c.lightAttenuationInited))
    result.add("attenuation", s.getValue(c.lightAttenuation))
    result.add("color", s.getValue(c.lightColor))

method visitProperties*(ls: LightSource, p: var PropertyVisitor) =
    p.visitProperty("ambient", ls.lightAmbient)
    p.visitProperty("diffuse", ls.lightDiffuse)
    p.visitProperty("specular", ls.lightSpecular)
    p.visitProperty("constant", ls.lightConstant)
    p.visitProperty("linear", ls.lightLinear)
    p.visitProperty("quadratic", ls.lightQuadratic)

    p.visitProperty("precomp_att", ls.lightAttenuation)
    p.visitProperty("use_precomp", ls.lightAttenuationInited)

    p.visitProperty("color", ls.lightColor)

registerComponent(LightSource)
