import nimx.image
import nimx.resource
import nimx.context
import nimx.portable_gl
import nimx.types
import nimx.system_logger
import nimx.matrixes

import tables
import hashes
import streams
import rod.node
import rod.component.mesh_component
import rod.component.material_shaders
import rod.component.light
import rod.component.camera
import rod.quaternion
import rod.vertex_data_info
import rod.viewport

import rod.animated_image

when not defined(ios) and not defined(android) and not defined(js):
    import opengl

type Attrib = enum
    aPosition
    aTexCoord
    aNormal
    aTangent
    aBinormal

type ShaderMacro = enum
    WITH_V_POSITION
    WITH_V_TEXCOORD
    WITH_V_NORMAL
    WITH_V_BINORMAL
    WITH_V_TANGENT
    WITH_AMBIENT_SAMPLER
    WITH_GLOSS_SAMPLER
    WITH_SPECULAR_SAMPLER
    WITH_REFLECTION_SAMPLER
    WITH_NORMAL_SAMPLER
    WITH_BUMP_SAMPLER
    WITH_MASK_SAMPLER
    WITH_FALLOF_SAMPLER
    WITH_MATERIAL_AMBIENT
    WITH_MATERIAL_EMISSION
    WITH_MATERIAL_DIFFUSE
    WITH_MATERIAL_SPECULAR
    WITH_MATERIAL_SHININESS
    WITH_LIGHT_POSITION
    WITH_LIGHT_AMBIENT
    WITH_LIGHT_DIFFUSE
    WITH_LIGHT_SPECULAR
    WITH_LIGHT_DYNAMIC_ATTENUATION
    WITH_LIGHT_PRECOMPUTED_ATTENUATION
    WITH_LIGHT_0
    WITH_LIGHT_1
    WITH_LIGHT_2
    WITH_LIGHT_3
    WITH_LIGHT_4
    WITH_LIGHT_5
    WITH_LIGHT_6
    WITH_LIGHT_7
    WITH_TBN_FROM_NORMALS
    WITH_RIM_LIGHT
    WITH_NORMALMAP_TO_SRGB
    WITH_MOTION_BLUR

type
    MaterialColor* = ref object
        emission: Color
        ambient: Color
        diffuse: Color
        specular: Color
        shininess: float32
        reflectivity: float32

        ambientInited: bool
        emissionInited: bool
        diffuseInited: bool
        specularInited: bool
        shininessInited: bool
        reflectivityInited: bool

    Material* = ref object of RootObj
        albedoTexture*: Image
        glossTexture*: Image
        specularTexture*: Image
        normalTexture*: Image
        bumpTexture*: Image
        reflectionTexture*: Image
        falloffTexture*: Image
        maskTexture*: Image

        color*: MaterialColor
        rimDensity: Coord

        currentLightSourcesCount: int
        isLightReceiver: bool

        bEnableBackfaceCulling*: bool
        blendEnable*: bool
        depthEnable*: bool
        isWireframe*: bool
        isRIM: bool
        isNormalSRGB: bool

        shader*: ProgramRef
        vertexShader: string
        fragmentShader: string
        bUserDefinedShader: bool
        bShaderNeedUpdate*: bool
        tempShaderMacroFlags: set[ShaderMacro]
        shaderMacroFlags: set[ShaderMacro]
        useManualShaderComposing*: bool

var shadersCache = initTable[set[ShaderMacro], tuple[shader: ProgramRef, refCount: int]]()

proc hash(sm: set[ShaderMacro]): Hash =
    var sum = ""
    for macros in sm:
        sum &= $macros
    result = sum.hash()
    result = !$result

template shaderNeedUpdate(m: Material) = m.bShaderNeedUpdate = true

proc emission*(m: Material): Color = result = m.color.emission
proc ambient*(m: Material): Color = result = m.color.ambient
proc diffuse*(m: Material): Color = result = m.color.diffuse
proc specular*(m: Material): Color = result = m.color.specular
proc shininess*(m: Material): Coord = result = m.color.shininess
proc reflectivity*(m: Material): Coord = result = m.color.reflectivity
proc rimDensity*(m: Material): Coord = result = m.rimDensity

template `emission=`*(m: Material, v: Color) =
    if not m.color.emissionInited:
        m.shaderMacroFlags.incl(WITH_MATERIAL_EMISSION)
        m.bShaderNeedUpdate = true
    m.color.emission = v
    m.color.emissionInited = true
template `ambient=`*(m: Material, v: Color) =
    if not m.color.ambientInited:
        m.shaderMacroFlags.incl(WITH_MATERIAL_AMBIENT)
        m.bShaderNeedUpdate = true
    m.color.ambient = v
    m.color.ambientInited = true
template `diffuse=`*(m: Material, v: Color) =
    if not m.color.diffuseInited:
        m.shaderMacroFlags.incl(WITH_MATERIAL_DIFFUSE)
        m.bShaderNeedUpdate = true
    m.color.diffuse = v
    m.color.diffuseInited = true
template `specular=`*(m: Material, v: Color) =
    if not m.color.specularInited:
        m.shaderMacroFlags.incl(WITH_MATERIAL_SPECULAR)
        m.bShaderNeedUpdate = true
    m.color.specular = v
    m.color.specularInited = true
template `shininess=`*(m: Material, s: Coord) =
    if not m.color.shininessInited:
        m.shaderMacroFlags.incl(WITH_MATERIAL_SHININESS)
        m.bShaderNeedUpdate = true
    m.color.shininess = s
    m.color.shininessInited = true
template `reflectivity=`*(m: Material, r: Coord) =
    m.color.reflectivity = r
    m.color.reflectivityInited = true
template `rimDensity=`*(m: Material, val: Coord) =
    m.rimDensity = val

template removeEmissionColor*(m: Material) =
    m.color.emissionInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_EMISSION)
    m.bShaderNeedUpdate = true
template removeAmbientColor*(m: Material) =
    m.color.ambientInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_AMBIENT)
    m.bShaderNeedUpdate = true
template removeDiffuseColor*(m: Material) =
    m.color.diffuseInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_DIFFUSE)
    m.bShaderNeedUpdate = true
template removeSpecularColor*(m: Material) =
    m.color.specularInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_SPECULAR)
    m.bShaderNeedUpdate = true
template removeShininess*(m: Material) =
    m.color.shininessInited = false
    m.shaderMacroFlags.excl(WITH_MATERIAL_SHININESS)
    m.bShaderNeedUpdate = true
template removeReflectivity*(m: Material) =
    m.color.reflectivityInited = false

proc isLightReceiver*(m: Material): bool =
    result = m.isLightReceiver

template `isLightReceiver=`*(m: Material, val: bool) =
    if m.isLightReceiver != val:
        m.isLightReceiver = val
        m.bShaderNeedUpdate = true

        if not val:
            for i in 0 .. m.currentLightSourcesCount - 1:
                m.shaderMacroFlags.excl(ShaderMacro(int(WITH_LIGHT_0) + i))

            m.shaderMacroFlags.excl(WITH_LIGHT_POSITION)
            m.shaderMacroFlags.excl(WITH_LIGHT_AMBIENT)
            m.shaderMacroFlags.excl(WITH_LIGHT_DIFFUSE)
            m.shaderMacroFlags.excl(WITH_LIGHT_SPECULAR)
            m.shaderMacroFlags.excl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
            m.shaderMacroFlags.excl(WITH_LIGHT_DYNAMIC_ATTENUATION)
        else:
            for i in 0 .. m.currentLightSourcesCount - 1:
                m.shaderMacroFlags.incl(ShaderMacro(int(WITH_LIGHT_0) + i))
            m.shaderMacroFlags.incl(WITH_LIGHT_POSITION)
            m.shaderMacroFlags.incl(WITH_LIGHT_AMBIENT)
            m.shaderMacroFlags.incl(WITH_LIGHT_DIFFUSE)
            m.shaderMacroFlags.incl(WITH_LIGHT_SPECULAR)
            m.shaderMacroFlags.incl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
            m.shaderMacroFlags.incl(WITH_LIGHT_DYNAMIC_ATTENUATION)

proc isRIM*(m: Material): bool =
    result = m.isRIM

template `isRIM=`*(m: Material, val: bool) =
    if m.isRIM != val:
        m.isRIM = val
        if val:
            m.shaderMacroFlags.incl(WITH_RIM_LIGHT)
        else:
            m.shaderMacroFlags.excl(WITH_RIM_LIGHT)
        m.bShaderNeedUpdate = true

template setupRIMLightTechnique*(m: Material) =
    if m.shader == invalidProgram:
        m.shaderMacroFlags.incl(WITH_RIM_LIGHT)
    else:
        gl.uniform1f(gl.getUniformLocation(m.shader, "uRimDensity"), m.rimDensity.GLfloat)

template setupNormalMappingTechniqueWithoutPrecomputedTangents*(m: Material) =
    if m.shader == invalidProgram:
        m.shaderMacroFlags.incl(WITH_TBN_FROM_NORMALS)

proc isNormalSRGB*(m: Material): bool =
    result = m.isNormalSRGB

template `isNormalSRGB=`*(m: Material, val: bool) =
    if m.isNormalSRGB != val:
        m.isNormalSRGB = val
        if val:
            m.shaderMacroFlags.incl(WITH_NORMALMAP_TO_SRGB)
        else:
            m.shaderMacroFlags.excl(WITH_NORMALMAP_TO_SRGB)
        m.bShaderNeedUpdate = true

template setupNormalSRGBTechnique*(m: Material) =
    if m.shader == invalidProgram:
        m.shaderMacroFlags.incl(WITH_NORMALMAP_TO_SRGB)

proc newDefaultMaterial*(): Material =
    result.new()
    result.currentLightSourcesCount = 0
    result.blendEnable = false
    result.depthEnable = true
    result.isWireframe = false
    result.isLightReceiver = true
    result.bEnableBackfaceCulling = true
    result.color.new()

proc setupVertexAttributes*(m: Material, vertInfo: VertexDataInfo) =
    let c = currentContext()
    let gl = c.gl

    var offset: int = 0

    if vertInfo.numOfCoordPerVert != 0:
        gl.enableVertexAttribArray(aPosition.GLuint)
        gl.vertexAttribPointer(aPosition.GLuint, vertInfo.numOfCoordPerVert, gl.FLOAT, false, vertInfo.stride.GLsizei , offset)
        offset += vertInfo.numOfCoordPerVert * sizeof(GLfloat)
    if vertInfo.numOfCoordPerTexCoord != 0:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_V_TEXCOORD)
        gl.enableVertexAttribArray(aTexCoord.GLuint)
        gl.vertexAttribPointer(aTexCoord.GLuint, vertInfo.numOfCoordPerTexCoord, gl.FLOAT, false, vertInfo.stride.GLsizei , offset)
        offset += vertInfo.numOfCoordPerTexCoord * sizeof(GLfloat)
    if vertInfo.numOfCoordPerNormal != 0:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_V_NORMAL)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        gl.enableVertexAttribArray(aNormal.GLuint)
        gl.vertexAttribPointer(aNormal.GLuint, vertInfo.numOfCoordPerNormal, gl.FLOAT, false, vertInfo.stride.GLsizei , offset)
        offset += vertInfo.numOfCoordPerNormal * sizeof(GLfloat)
    if vertInfo.numOfCoordPerTangent != 0:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_V_TANGENT)
        gl.enableVertexAttribArray(aTangent.GLuint)
        gl.vertexAttribPointer(aTangent.GLuint, vertInfo.numOfCoordPerTangent, gl.FLOAT, false, vertInfo.stride.GLsizei , offset)
        offset += vertInfo.numOfCoordPerTangent * sizeof(GLfloat)
    if vertInfo.numOfCoordPerBinormal != 0:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_V_BINORMAL)
        gl.enableVertexAttribArray(aBinormal.GLuint)
        gl.vertexAttribPointer(aBinormal.GLuint, vertInfo.numOfCoordPerBinormal, gl.FLOAT, false, vertInfo.stride.GLsizei , offset)
        offset += vertInfo.numOfCoordPerBinormal * sizeof(GLfloat)

proc setupSamplerAttributes(m: Material) =
    let c = currentContext()
    let gl = c.gl

    var theQuad {.noinit.}: array[4, GLfloat]
    var textureIndex : GLint = 0

    if not m.albedoTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_AMBIENT_SAMPLER)
        else:
            if m.albedoTexture.isLoaded:
                gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.albedoTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uTexUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m.shader, "texUnit"), textureIndex)
                inc textureIndex
    if not m.glossTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_GLOSS_SAMPLER)
        else:
            if m.glossTexture.isLoaded:
                gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.glossTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uGlossUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m.shader, "glossMapUnit"), textureIndex)
                inc textureIndex
    if not m.specularTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_SPECULAR_SAMPLER)
        else:
            if m.specularTexture.isLoaded:
                gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.specularTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uSpecularUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m.shader, "specularMapUnit"), textureIndex)
                inc textureIndex
    if not m.normalTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_NORMAL_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.normalTexture.isLoaded:
                gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.normalTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uNormalUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m.shader, "normalMapUnit"), textureIndex)
                inc textureIndex
    if not m.bumpTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_BUMP_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.bumpTexture.isLoaded:
                gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.bumpTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uBumpUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m.shader, "bumpMapUnit"), textureIndex)
                inc textureIndex
    if not m.reflectionTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_REFLECTION_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.reflectionTexture.isLoaded:
                gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.reflectionTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uReflectUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m.shader, "reflectMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m.shader, "uReflectivity"), m.color.reflectivity)
                inc textureIndex
    if not m.falloffTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_FALLOF_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.falloffTexture.isLoaded:
                gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.falloffTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uFallofUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m.shader, "falloffMapUnit"), textureIndex)
                inc textureIndex
    if not m.maskTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_MASK_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.maskTexture.isLoaded:
                gl.activeTexture(gl.TEXTURE0 + textureIndex.GLenum)
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.maskTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uMaskUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m.shader, "maskMapUnit"), textureIndex)
                inc textureIndex

proc setupMaterialAttributes(m: Material, n: Node) =
    if not m.color.isNil:
        let c = currentContext()
        let gl = c.gl

        if m.color.ambientInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_AMBIENT)
            else:
                c.setColorUniform(m.shader, "uMaterialAmbient", m.color.ambient)
        if m.color.emissionInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_EMISSION)
            else:
                c.setColorUniform(m.shader, "uMaterialEmission", m.color.emission)
        if m.color.diffuseInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_DIFFUSE)
            else:
                c.setColorUniform(m.shader, "uMaterialDiffuse", m.color.diffuse)
        if m.color.specularInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_SPECULAR)
            else:
                c.setColorUniform(m.shader, "uMaterialSpecular", m.color.specular)
        if m.color.shininessInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_SHININESS)
            else:
                gl.uniform1f(gl.getUniformLocation(m.shader, "uMaterialShininess"), m.color.shininess)
        if m.shader != invalidProgram:
            gl.uniform1f(gl.getUniformLocation(m.shader, "uMaterialTransparency"), n.alpha)

proc setupLightAttributes(m: Material, v: SceneView) =
    var lightsCount = 0

    if not v.lightSources.isNil and v.lightSources.len != 0:
        let c = currentContext()
        let gl = c.gl

        for ls in values v.lightSources:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_LIGHT_POSITION)
            else:
                let lightWorldPos = ls.node.worldPos()
                let lightPosition = v.viewMatrixCached * newVector4(lightWorldPos.x, lightWorldPos.y, lightWorldPos.z, 1.0)
                gl.uniform4fv(gl.getUniformLocation(m.shader, "uLightPosition" & $lightsCount), lightPosition)
            if ls.lightAmbientInited:
                if m.shader == invalidProgram:
                    m.shaderMacroFlags.incl(WITH_LIGHT_AMBIENT)
                else:
                    gl.uniform1f(gl.getUniformLocation(m.shader, "uLightAmbient" & $lightsCount), ls.lightAmbient)
            if ls.lightDiffuseInited:
                if m.shader == invalidProgram:
                    m.shaderMacroFlags.incl(WITH_LIGHT_DIFFUSE)
                else:
                    gl.uniform1f(gl.getUniformLocation(m.shader, "uLightDiffuse" & $lightsCount), ls.lightDiffuse)
            if ls.lightSpecularInited:
                if m.shader == invalidProgram:
                    m.shaderMacroFlags.incl(WITH_LIGHT_SPECULAR)
                else:
                    gl.uniform1f(gl.getUniformLocation(m.shader, "uLightSpecular" & $lightsCount), ls.lightSpecular)
            if ls.lightAttenuationInited:
                if m.shader == invalidProgram:
                    m.shaderMacroFlags.incl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
                else:
                    gl.uniform1f(gl.getUniformLocation(m.shader, "uAttenuation" & $lightsCount), ls.lightAttenuation)
            elif ls.lightConstantInited and ls.lightLinearInited and ls.lightQuadraticInited:
                if m.shader == invalidProgram:
                    m.shaderMacroFlags.incl(WITH_LIGHT_DYNAMIC_ATTENUATION)
                else:
                    gl.uniform1f(gl.getUniformLocation(m.shader, "uLightConstant" & $lightsCount), ls.lightConstant)
                    gl.uniform1f(gl.getUniformLocation(m.shader, "uLightLinear" & $lightsCount), ls.lightLinear)
                    gl.uniform1f(gl.getUniformLocation(m.shader, "uLightQuadratic" & $lightsCount), ls.lightQuadratic)
            inc(lightsCount)

    if m.currentLightSourcesCount != lightsCount:
        m.shaderNeedUpdate()

        while lightsCount != m.currentLightSourcesCount:
            if m.currentLightSourcesCount < lightsCount:
                m.shaderMacroFlags.incl(ShaderMacro(int(WITH_LIGHT_0) + m.currentLightSourcesCount))
                inc(m.currentLightSourcesCount)
            else:
                dec(m.currentLightSourcesCount)
                m.shaderMacroFlags.excl(ShaderMacro(int(WITH_LIGHT_0) + m.currentLightSourcesCount))

        if lightsCount == 0:
            m.shaderMacroFlags.excl(WITH_LIGHT_POSITION)
            m.shaderMacroFlags.excl(WITH_LIGHT_AMBIENT)
            m.shaderMacroFlags.excl(WITH_LIGHT_DIFFUSE)
            m.shaderMacroFlags.excl(WITH_LIGHT_SPECULAR)
            m.shaderMacroFlags.excl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
            m.shaderMacroFlags.excl(WITH_LIGHT_DYNAMIC_ATTENUATION)
        else:
            m.shaderMacroFlags.incl(WITH_LIGHT_POSITION)
            m.shaderMacroFlags.incl(WITH_LIGHT_AMBIENT)
            m.shaderMacroFlags.incl(WITH_LIGHT_DIFFUSE)
            m.shaderMacroFlags.incl(WITH_LIGHT_SPECULAR)
            m.shaderMacroFlags.incl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
            m.shaderMacroFlags.incl(WITH_LIGHT_DYNAMIC_ATTENUATION)

template setupTransform*(m: Material, n: Node) =
    let c = currentContext()
    let gl = c.gl

    var modelViewMatrix: Matrix4
    var normalMatrix: Matrix3

    modelViewMatrix = n.sceneView.viewMatrixCached * n.worldTransform

    if n.scale.x != 0 and n.scale.y != 0 and n.scale.z != 0:
        modelViewMatrix.toInversedMatrix3(normalMatrix)
        normalMatrix.transpose()
    else:
        normalMatrix.loadIdentity()

    gl.uniformMatrix4fv(gl.getUniformLocation(m.shader, "modelViewMatrix"), false, modelViewMatrix)
    gl.uniformMatrix3fv(gl.getUniformLocation(m.shader, "normalMatrix"), false, normalMatrix)
    c.setTransformUniform(m.shader) # setup modelViewProjectionMatrix

    # let worldCamPos = n.sceneView.camera.node.translation
    # let camPos = newVector4(worldCamPos.x, worldCamPos.y, worldCamPos.z, 1.0)
    # gl.uniform4fv(gl.getUniformLocation(m.shader, "uCamPosition"), camPos)

proc createShader(m: Material) =
    let c = currentContext()
    let gl = c.gl

    if not shadersCache.contains(m.shaderMacroFlags):
        var commonShaderDefines = ""

        for mcrs in m.shaderMacroFlags:
            commonShaderDefines &= """#define """ & $mcrs & "\n"

        if m.vertexShader.len == 0:
            m.vertexShader = commonShaderDefines & materialVertexShaderDefault
        else:
            m.vertexShader = commonShaderDefines & m.vertexShader

        if m.fragmentShader.len == 0:
            m.fragmentShader = commonShaderDefines & materialFragmentShaderDefault
        else:
            m.fragmentShader = commonShaderDefines & m.fragmentShader

        m.shader = gl.newShaderProgram(m.vertexShader, m.fragmentShader, [(aPosition.GLuint, $aPosition), (aTexCoord.GLuint, $aTexCoord),
                                        (aNormal.GLuint, $aNormal), (aTangent.GLuint, $aTangent), (aBinormal.GLuint, $aBinormal)])
        m.bShaderNeedUpdate = false

        shadersCache[m.shaderMacroFlags] = (m.shader, 1)
    else:
        m.shader = shadersCache[m.shaderMacroFlags].shader
        shadersCache[m.shaderMacroFlags].refCount += 1
        m.bShaderNeedUpdate = false

    m.tempShaderMacroFlags = m.shaderMacroFlags

proc assignShaders*(m: Material, vertexShader: string = "", fragmentShader: string = "") =
    m.vertexShader = vertexShader
    m.fragmentShader = fragmentShader
    m.shaderNeedUpdate()

proc assignShadersWithResource*(m: Material, vertexShader: string = "", fragmentShader: string = "") =
    m.bUserDefinedShader = true
    var bVertexShaderSourceLoaded, bFragmentShaderSourceLoaded: bool

    template shaderSourceLoaded(bVertexShaderSourceLoaded, bFragmentShaderSourceLoaded: bool) =
        if bVertexShaderSourceLoaded and bFragmentShaderSourceLoaded:
            m.shaderNeedUpdate()

    if vertexShader != "":
        loadResourceAsync vertexShader, proc(s: Stream) =
            m.vertexShader = s.readAll()
            s.close()
            bVertexShaderSourceLoaded = true
            shaderSourceLoaded(bVertexShaderSourceLoaded, bFragmentShaderSourceLoaded)
    else:
        m.vertexShader = materialVertexShaderDefault

    if fragmentShader != "":
        loadResourceAsync fragmentShader, proc(s: Stream) =
            m.fragmentShader = s.readAll()
            s.close()
            bFragmentShaderSourceLoaded = true
            shaderSourceLoaded(bVertexShaderSourceLoaded, bFragmentShaderSourceLoaded)
    else:
        m.fragmentShader = materialFragmentShaderDefault

    shaderSourceLoaded(bVertexShaderSourceLoaded, bFragmentShaderSourceLoaded)

method initSetup*(m: Material) {.base.} = discard

method updateSetup*(m: Material, n: Node) {.base.} =
    let c = currentContext()
    let gl = c.gl

    if (m.shader == invalidProgram or m.bShaderNeedUpdate) and not m.useManualShaderComposing:
        if m.shader != invalidProgram:
            if not m.bUserDefinedShader:
                if shadersCache.contains(m.tempShaderMacroFlags):
                    if shadersCache[m.tempShaderMacroFlags].refCount <= 1:
                        shadersCache.del(m.tempShaderMacroFlags)
                        gl.deleteProgram(m.shader)
                    else:
                        shadersCache[m.tempShaderMacroFlags].refCount -= 1

                var s: set[ShaderMacro]
                m.tempShaderMacroFlags = s

                m.shader = invalidProgram
                m.vertexShader = ""
                m.fragmentShader = ""

        m.setupSamplerAttributes()
        m.setupMaterialAttributes(n)
        if m.isLightReceiver:
            m.setupLightAttributes(n.sceneView)
        # setup shader techniques
        m.setupNormalMappingTechniqueWithoutPrecomputedTangents()
        if m.isRIM:
            m.setupRIMLightTechnique()
        if m.isNormalSRGB:
            m.setupNormalSRGBTechnique()
        m.createShader()

    gl.useProgram(m.shader)
    m.setupSamplerAttributes()
    m.setupMaterialAttributes(n)
    if m.isLightReceiver:
        m.setupLightAttributes(n.sceneView)
    if m.isRIM:
        m.setupRIMLightTechnique()
    m.setupTransform(n)

    if n.alpha < 1.0 or m.blendEnable:
        gl.enable(gl.BLEND)
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    else:
        gl.disable(gl.BLEND)
    if m.depthEnable:
        gl.enable(gl.DEPTH_TEST)
    when not defined(ios) and not defined(android) and not defined(js):
        glPolygonMode(GL_FRONT_AND_BACK, if m.isWireframe: GL_LINE else: GL_FILL)
