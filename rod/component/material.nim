import tables, hashes, streams
import nimx / [ image, context, portable_gl, types, matrixes ]

import rod.node
import rod.component.mesh_component
import rod.component.material_shaders
import rod.component.light
import rod.component.camera
import rod.quaternion
import rod.vertex_data_info
import rod.viewport
import rod.postprocess_context

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
    WITH_MATCAP_R
    WITH_MATCAP_G
    WITH_MATCAP_B
    WITH_MATCAP_A
    WITH_MATCAP_MASK_SAMPLER
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
    WITH_GAMMA_CORRECTION
    WITH_SHADOW

type
    MaterialColor* = ref object
        emission: Color
        ambient: Color
        diffuse: Color
        specular: Color
        shininess: float32

        ambientInited: bool
        emissionInited: bool
        diffuseInited: bool
        specularInited: bool
        shininessInited: bool

    Material* = ref object of RootObj
        matcapTextureR: Image
        matcapTextureG: Image
        matcapTextureB: Image
        matcapTextureA: Image
        matcapMaskTexture: Image
        albedoTexture: Image
        glossTexture: Image
        specularTexture: Image
        normalTexture: Image
        bumpTexture: Image
        reflectionTexture: Image
        falloffTexture: Image
        maskTexture: Image

        matcapPercentR*: float32
        matcapPercentG*: float32
        matcapPercentB*: float32
        matcapPercentA*: float32
        matcapMaskPercent*: float32
        albedoPercent*: float32
        glossPercent*: float32
        specularPercent*: float32
        normalPercent*: float32
        bumpPercent*: float32
        reflectionPercent*: float32
        falloffPercent*: float32
        maskPercent*: float32

        color*: MaterialColor
        rimDensity: Coord
        rimColor: Color

        currentLightSourcesCount: int
        isLightReceiver: bool

        bEnableBackfaceCulling*: bool
        blendEnable*: bool
        depthEnable*: bool
        isWireframe*: bool
        isRIM: bool
        isNormalSRGB: bool
        gammaCorrection: bool

        shader*: ProgramRef
        vertexShader: string
        fragmentShader: string
        bUserDefinedShader: bool
        bShaderNeedUpdate*: bool
        tempShaderMacroFlags: set[ShaderMacro]
        shaderMacroFlags: set[ShaderMacro]
        useManualShaderComposing*: bool
        uniformLocationCache*: seq[UniformLocation]
        iUniform: int

var shadersCache = initTable[set[ShaderMacro], tuple[shader: ProgramRef, refCount: int]]()

template getUniformLocation*(gl: GL, m: Material, name: cstring): UniformLocation =
    inc m.iUniform
    if m.uniformLocationCache.len - 1 < m.iUniform:
        m.uniformLocationCache.add(gl.getUniformLocation(m.shader, name))
    m.uniformLocationCache[m.iUniform]

template setColorUniform(c: GraphicsContext, m: Material, name: cstring, col: Color) =
    c.setColorUniform(c.gl.getUniformLocation(m, name), col)

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
proc rimDensity*(m: Material): Coord = result = m.rimDensity
proc rimColor*(m: Material): Color = result = m.rimColor
proc matcapTextureR*(m: Material): Image = result = m.matcapTextureR
proc matcapTextureG*(m: Material): Image = result = m.matcapTextureG
proc matcapTextureB*(m: Material): Image = result = m.matcapTextureB
proc matcapTextureA*(m: Material): Image = result = m.matcapTextureA
proc matcapMaskTexture*(m: Material): Image = result = m.matcapMaskTexture
proc albedoTexture*(m: Material): Image = result = m.albedoTexture
proc glossTexture*(m: Material): Image = result = m.glossTexture
proc specularTexture*(m: Material): Image = result = m.specularTexture
proc normalTexture*(m: Material): Image = result = m.normalTexture
proc bumpTexture*(m: Material): Image = result = m.bumpTexture
proc reflectionTexture*(m: Material): Image = result = m.reflectionTexture
proc falloffTexture*(m: Material): Image = result = m.falloffTexture
proc maskTexture*(m: Material): Image = result = m.maskTexture
proc gammaCorrection*(m: Material): bool = result = m.gammaCorrection

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
template `rimDensity=`*(m: Material, val: Coord) =
    m.rimDensity = val
template `rimColor=`*(m: Material, val: Color) =
    m.rimColor = val
template `matcapTextureR=`*(m: Material, i: Image) =
    if m.matcapTextureR.isNil:
        m.shaderMacroFlags.incl(WITH_MATCAP_R)
        m.bShaderNeedUpdate = true
    m.matcapTextureR = i
    if m.matcapTextureR.isNil:
        m.shaderMacroFlags.excl(WITH_MATCAP_R)
        m.bShaderNeedUpdate = true
template `matcapTextureG=`*(m: Material, i: Image) =
    if m.matcapTextureG.isNil:
        m.shaderMacroFlags.incl(WITH_MATCAP_G)
        m.bShaderNeedUpdate = true
    m.matcapTextureG = i
    if m.matcapTextureG.isNil:
        m.shaderMacroFlags.excl(WITH_MATCAP_G)
        m.bShaderNeedUpdate = true
template `matcapTextureB=`*(m: Material, i: Image) =
    if m.matcapTextureB.isNil:
        m.shaderMacroFlags.incl(WITH_MATCAP_B)
        m.bShaderNeedUpdate = true
    m.matcapTextureB = i
    if m.matcapTextureB.isNil:
        m.shaderMacroFlags.excl(WITH_MATCAP_B)
        m.bShaderNeedUpdate = true
template `matcapTextureA=`*(m: Material, i: Image) =
    if m.matcapTextureA.isNil:
        m.shaderMacroFlags.incl(WITH_MATCAP_A)
        m.bShaderNeedUpdate = true
    m.matcapTextureA = i
    if m.matcapTextureA.isNil:
        m.shaderMacroFlags.excl(WITH_MATCAP_A)
        m.bShaderNeedUpdate = true
template `matcapMaskTexture=`*(m: Material, i: Image) =
    if m.matcapMaskTexture.isNil:
        m.shaderMacroFlags.incl(WITH_MATCAP_MASK_SAMPLER)
        m.bShaderNeedUpdate = true
    m.matcapMaskTexture = i
    if m.matcapMaskTexture.isNil:
        m.shaderMacroFlags.excl(WITH_MATCAP_MASK_SAMPLER)
        m.bShaderNeedUpdate = true
template `albedoTexture=`*(m: Material, i: Image) =
    if m.albedoTexture.isNil:
        m.shaderMacroFlags.incl(WITH_AMBIENT_SAMPLER)
        m.bShaderNeedUpdate = true
    m.albedoTexture = i
    if m.albedoTexture.isNil:
        m.shaderMacroFlags.excl(WITH_AMBIENT_SAMPLER)
        m.bShaderNeedUpdate = true
template `glossTexture=`*(m: Material, i: Image) =
    if m.glossTexture.isNil:
        m.shaderMacroFlags.incl(WITH_GLOSS_SAMPLER)
        m.bShaderNeedUpdate = true
    m.glossTexture = i
    if m.glossTexture.isNil:
        m.shaderMacroFlags.excl(WITH_GLOSS_SAMPLER)
        m.bShaderNeedUpdate = true
template `specularTexture=`*(m: Material, i: Image) =
    if m.specularTexture.isNil:
        m.shaderMacroFlags.incl(WITH_SPECULAR_SAMPLER)
        m.bShaderNeedUpdate = true
    m.specularTexture = i
    if m.specularTexture.isNil:
        m.shaderMacroFlags.excl(WITH_SPECULAR_SAMPLER)
        m.bShaderNeedUpdate = true
template `normalTexture=`*(m: Material, i: Image) =
    if m.normalTexture.isNil:
        m.shaderMacroFlags.incl(WITH_NORMAL_SAMPLER)
        m.bShaderNeedUpdate = true
    m.normalTexture = i
    if m.normalTexture.isNil:
        m.shaderMacroFlags.excl(WITH_NORMAL_SAMPLER)
        m.bShaderNeedUpdate = true
template `bumpTexture=`*(m: Material, i: Image) =
    if m.bumpTexture.isNil:
        m.shaderMacroFlags.incl(WITH_BUMP_SAMPLER)
        m.bShaderNeedUpdate = true
    m.bumpTexture = i
    if m.bumpTexture.isNil:
        m.shaderMacroFlags.excl(WITH_BUMP_SAMPLER)
        m.bShaderNeedUpdate = true
template `reflectionTexture=`*(m: Material, i: Image) =
    if m.reflectionTexture.isNil:
        m.shaderMacroFlags.incl(WITH_REFLECTION_SAMPLER)
        m.bShaderNeedUpdate = true
    m.reflectionTexture = i
    if m.reflectionTexture.isNil:
        m.shaderMacroFlags.excl(WITH_REFLECTION_SAMPLER)
        m.bShaderNeedUpdate = true
template `falloffTexture=`*(m: Material, i: Image) =
    if m.falloffTexture.isNil:
        m.shaderMacroFlags.incl(WITH_FALLOF_SAMPLER)
        m.bShaderNeedUpdate = true
    m.falloffTexture = i
    if m.falloffTexture.isNil:
        m.shaderMacroFlags.excl(WITH_FALLOF_SAMPLER)
        m.bShaderNeedUpdate = true
template `maskTexture=`*(m: Material, i: Image) =
    if m.maskTexture.isNil:
        m.shaderMacroFlags.incl(WITH_MASK_SAMPLER)
        m.bShaderNeedUpdate = true
    m.maskTexture = i
    if m.maskTexture.isNil:
        m.shaderMacroFlags.excl(WITH_MASK_SAMPLER)
        m.bShaderNeedUpdate = true
template `gammaCorrection=`*(m: Material, v: bool) =
    m.gammaCorrection = v
    if m.gammaCorrection: m.shaderMacroFlags.incl(WITH_GAMMA_CORRECTION)
    else: m.shaderMacroFlags.excl(WITH_GAMMA_CORRECTION)
    m.bShaderNeedUpdate = true

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

proc isLightReceiver*(m: Material): bool =
    result = m.isLightReceiver

template `isLightReceiver=`*(m: Material, val: bool) =
    if m.isLightReceiver != val:
        m.isLightReceiver = val
        m.bShaderNeedUpdate = true

        if not val:
            for i in 0 ..< m.currentLightSourcesCount:
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
    let c = currentContext()
    let gl = c.gl
    if m.shader == invalidProgram:
        m.shaderMacroFlags.incl(WITH_RIM_LIGHT)
    else:
        gl.uniform1f(gl.getUniformLocation(m, "uRimDensity"), m.rimDensity.GLfloat)
        c.setColorUniform(m, "uRimColor", m.rimColor)

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
    result.matcapPercentR = 1.0
    result.matcapPercentG = 1.0
    result.matcapPercentB = 1.0
    result.matcapPercentA = 1.0
    result.matcapMaskPercent = 1.0
    result.albedoPercent = 1.0
    result.glossPercent = 1.0
    result.specularPercent = 1.0
    result.normalPercent = 1.0
    result.bumpPercent = 1.0
    result.reflectionPercent = 1.0
    result.falloffPercent = 1.0
    result.maskPercent = 1.0

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

var postContext: PostprocessContext

proc setupShadow*(m: Material, pc: PostprocessContext) =
    postContext = pc

proc setupSamplerAttributes(m: Material) =
    let c = currentContext()
    let gl = c.gl

    var theQuad {.noinit.}: array[4, GLfloat]
    var textureIndex : GLint = 0

    if not m.matcapTextureR.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_MATCAP_R)
        else:
            if m.matcapTextureR.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.matcapTextureR, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uMatcapUnitCoordsR"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "matcapUnitR"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uMatcapPercentR"), m.matcapPercentR)
                inc textureIndex
    if not m.matcapTextureG.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_MATCAP_G)
        else:
            if m.matcapTextureG.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.matcapTextureG, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uMatcapUnitCoordsG"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "matcapUnitG"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uMatcapPercentG"), m.matcapPercentG)
                inc textureIndex
    if not m.matcapTextureB.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_MATCAP_B)
        else:
            if m.matcapTextureB.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.matcapTextureB, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uMatcapUnitCoordsB"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "matcapUnitB"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uMatcapPercentB"), m.matcapPercentB)
                inc textureIndex
    if not m.matcapTextureA.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_MATCAP_A)
        else:
            if m.matcapTextureA.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.matcapTextureA, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uMatcapUnitCoordsA"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "matcapUnitA"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uMatcapPercentA"), m.matcapPercentA)
                inc textureIndex
    if not m.matcapMaskTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_MATCAP_MASK_SAMPLER)
        else:
            if m.matcapMaskTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.matcapMaskTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uMatcapMaskUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "matcapMaskUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uMatcapMaskPercent"), m.matcapMaskPercent)
                inc textureIndex
    if not m.albedoTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_AMBIENT_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_TEXCOORD)
        else:
            if m.albedoTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.albedoTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uTexUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "texUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uTexUnitPercent"), m.albedoPercent)
                inc textureIndex
    if not m.glossTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_GLOSS_SAMPLER)
        else:
            if m.glossTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.glossTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uGlossUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "glossMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uGlossPercent"), m.glossPercent)
                inc textureIndex
    if not m.specularTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_SPECULAR_SAMPLER)
        else:
            if m.specularTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.specularTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uSpecularUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "specularMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uSpecularPercent"), m.specularPercent)
                inc textureIndex
    if not m.normalTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_NORMAL_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.normalTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.normalTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uNormalUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "normalMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uNormalPercent"), m.normalPercent)
                inc textureIndex
    if not m.bumpTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_BUMP_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.bumpTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.bumpTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uBumpUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "bumpMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uBumpPercent"), m.bumpPercent)
                inc textureIndex
    if not m.reflectionTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_REFLECTION_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.reflectionTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.reflectionTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uReflectUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "reflectMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uReflectionPercent"), m.reflectionPercent)
                inc textureIndex
    if not m.falloffTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_FALLOF_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.falloffTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.falloffTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uFallofUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "falloffMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uFalloffPercent"), m.falloffPercent)
                inc textureIndex
    if not m.maskTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_MASK_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.maskTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.maskTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uMaskUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "maskMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uMaskPercent"), m.maskPercent)
                inc textureIndex
    if not m.maskTexture.isNil:
        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_MASK_SAMPLER)
            m.shaderMacroFlags.incl(WITH_V_POSITION)
        else:
            if m.maskTexture.isLoaded:
                gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
                gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(m.maskTexture, gl, theQuad))
                gl.uniform4fv(gl.getUniformLocation(m, "uMaskUnitCoords"), theQuad)
                gl.uniform1i(gl.getUniformLocation(m, "maskMapUnit"), textureIndex)
                gl.uniform1f(gl.getUniformLocation(m, "uMaskPercent"), m.maskPercent)
                inc textureIndex
    if not postContext.isNil and not postContext.depthImage.isNil:
        if not m.shaderMacroFlags.contains(WITH_SHADOW):
            m.shaderMacroFlags.incl(WITH_SHADOW)
            m.shaderNeedUpdate()

        if m.shader == invalidProgram:
            m.shaderMacroFlags.incl(WITH_SHADOW)
        else:
            gl.activeTexture(GLenum(int(gl.TEXTURE0) + textureIndex))
            gl.bindTexture(gl.TEXTURE_2D, getTextureQuad(postContext.depthImage, gl, theQuad))
            gl.uniform4fv(gl.getUniformLocation(m, "uDepthUnitCoords"), theQuad)
            gl.uniform1i(gl.getUniformLocation(m, "depthMapUnit"), textureIndex)
            inc textureIndex

            gl.uniformMatrix4fv(gl.getUniformLocation(m, "lightMatrix"), false, postContext.depthMatrix)

proc setupMaterialAttributes(m: Material) =
    if not m.color.isNil:
        let c = currentContext()
        let gl = c.gl

        if m.color.ambientInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_AMBIENT)
            else:
                c.setColorUniform(m, "uMaterialAmbient", m.color.ambient)
        if m.color.emissionInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_EMISSION)
            else:
                c.setColorUniform(m, "uMaterialEmission", m.color.emission)
        if m.color.diffuseInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_DIFFUSE)
            else:
                c.setColorUniform(m, "uMaterialDiffuse", m.color.diffuse)
        if m.color.specularInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_SPECULAR)
            else:
                c.setColorUniform(m, "uMaterialSpecular", m.color.specular)
        if m.color.shininessInited:
            if m.shader == invalidProgram:
                m.shaderMacroFlags.incl(WITH_MATERIAL_SHININESS)
            else:
                gl.uniform1f(gl.getUniformLocation(m, "uMaterialShininess"), m.color.shininess)
        if m.shader != invalidProgram:
            gl.uniform1f(gl.getUniformLocation(m, "uMaterialTransparency"), c.alpha)

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
                c.setColorUniform(m.shader, "uLightColor" & $lightsCount, ls.lightColor)
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
                if not m.shaderMacroFlags.contains(WITH_LIGHT_PRECOMPUTED_ATTENUATION):
                    m.shaderMacroFlags.excl(WITH_LIGHT_DYNAMIC_ATTENUATION)
                    m.shaderNeedUpdate()

                if m.shader == invalidProgram:
                    m.shaderMacroFlags.incl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
                else:
                    gl.uniform1f(gl.getUniformLocation(m.shader, "uAttenuation" & $lightsCount), ls.lightAttenuation)
            else:
                if not m.shaderMacroFlags.contains(WITH_LIGHT_DYNAMIC_ATTENUATION):
                    m.shaderMacroFlags.excl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
                    m.shaderNeedUpdate()

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
            m.shaderMacroFlags.excl({WITH_LIGHT_POSITION, WITH_LIGHT_POSITION,
                WITH_LIGHT_AMBIENT, WITH_LIGHT_DIFFUSE, WITH_LIGHT_SPECULAR,
                WITH_LIGHT_PRECOMPUTED_ATTENUATION, WITH_LIGHT_DYNAMIC_ATTENUATION})
        else:
            m.shaderMacroFlags.incl({WITH_LIGHT_POSITION, WITH_LIGHT_AMBIENT,
                WITH_LIGHT_DIFFUSE, WITH_LIGHT_SPECULAR})

            for ls in values v.lightSources:
                if ls.lightAttenuationInited:
                    m.shaderMacroFlags.incl(WITH_LIGHT_PRECOMPUTED_ATTENUATION)
                elif ls.lightConstantInited and ls.lightLinearInited and ls.lightQuadraticInited:
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

    gl.uniformMatrix4fv(gl.getUniformLocation(m, "modelMatrix"), false, n.worldTransform)
    gl.uniformMatrix4fv(gl.getUniformLocation(m, "modelViewMatrix"), false, modelViewMatrix)
    gl.uniformMatrix3fv(gl.getUniformLocation(m, "normalMatrix"), false, normalMatrix)
    c.setTransformUniform(m.shader) # setup modelViewProjectionMatrix

proc createShader(m: Material) =
    m.uniformLocationCache = @[]
    m.iUniform = -1

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

when false:
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

    m.iUniform = -1

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
        m.setupMaterialAttributes()
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
    m.setupMaterialAttributes()
    if m.isLightReceiver:
        m.setupLightAttributes(n.sceneView)
    if m.isRIM:
        m.setupRIMLightTechnique()

    if c.alpha < 1.0 or m.blendEnable:
        gl.enable(gl.BLEND)
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    else:
        gl.disable(gl.BLEND)
    if m.depthEnable:
        gl.enable(gl.DEPTH_TEST)
    when not defined(ios) and not defined(android) and not defined(js) and not defined(emscripten):
        glPolygonMode(GL_FRONT_AND_BACK, if m.isWireframe: GL_LINE else: GL_FILL)
