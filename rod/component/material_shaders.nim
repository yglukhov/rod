const materialVertexShaderDefault* = """
attribute vec4 aPosition;
attribute vec4 aNormal;
attribute vec4 aTangent;
attribute vec4 aBinormal;
attribute vec2 aTexCoord;

#ifdef WITH_V_POSITION
varying vec3 vPosition;
#endif
#ifdef WITH_V_NORMAL
varying vec3 vNormal;
#endif
#ifdef WITH_V_TANGENT
varying vec3 vTangent;
varying vec3 vBinormal;
#endif
#ifdef WITH_V_TEXCOORD
varying vec2 vTexCoord;
#endif

uniform mat4 modelViewProjectionMatrix;
uniform mat4 modelViewMatrix;
uniform mat3 normalMatrix;

void main() {
#ifdef WITH_V_POSITION
    vPosition = vec4(modelViewMatrix * aPosition).xyz;
#endif
#ifdef WITH_V_NORMAL
    vNormal = normalize(normalMatrix * aNormal.xyz);
#endif
#ifdef WITH_V_TANGENT
    vTangent = normalize(normalMatrix * aTangent.xyz);
    #ifdef WITH_V_BINORMAL
        vBinormal = normalize(normalMatrix * aBinormal.xyz);
    #else
        vec3 bitangent = cross(vTangent.xyz, vNormal.xyz);
        vBinormal = normalize(bitangent);
    #endif
#endif
#ifdef WITH_V_TEXCOORD
    vTexCoord = aTexCoord;
#endif
    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0);
}
"""
const materialFragmentShaderDefault* = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

#ifdef WITH_V_POSITION
varying vec3 vPosition;
#endif
#ifdef WITH_V_NORMAL
varying vec3 vNormal;
#endif
#ifdef WITH_V_TANGENT
varying vec3 vTangent;
varying vec3 vBinormal;
#endif
#ifdef WITH_V_TEXCOORD
varying vec2 vTexCoord;
#endif
#ifdef WITH_MATCAP_SAMPLER
uniform sampler2D matcapUnit;
uniform vec4 uMatcapUnitCoords;
uniform float uMatcapPercent;
#endif
#ifdef WITH_MATCAP_INTERPOLATE_SAMPLER
uniform sampler2D matcapUnitInterpolate;
uniform vec4 uMatcapUnitCoordsInterpolate;
uniform float uMatcapPercentInterpolate;
uniform float uMatcapMixPercent;
#endif
#ifdef WITH_AMBIENT_SAMPLER
uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform float uTexUnitPercent;
#endif
#ifdef WITH_GLOSS_SAMPLER
uniform sampler2D glossMapUnit;
uniform vec4 uGlossUnitCoords;
uniform float uGlossPercent;
#endif
#ifdef WITH_SPECULAR_SAMPLER
uniform sampler2D specularMapUnit;
uniform vec4 uSpecularUnitCoords;
uniform float uSpecularPercent;
#endif
#ifdef WITH_BUMP_SAMPLER
uniform sampler2D bumpMapUnit;
uniform vec4 uBumpUnitCoords;
uniform float uBumpPercent;
#endif
#ifdef WITH_NORMAL_SAMPLER
uniform sampler2D normalMapUnit;
uniform vec4 uNormalUnitCoords;
uniform float uNormalPercent;
#endif
#ifdef WITH_REFLECTION_SAMPLER
uniform sampler2D reflectMapUnit;
uniform vec4 uReflectUnitCoords;
uniform float uReflectionPercent;
#endif
#ifdef WITH_FALLOF_SAMPLER
uniform sampler2D falloffMapUnit;
uniform vec4 uFallofUnitCoords;
uniform float uFalloffPercent;
#endif
#ifdef WITH_MASK_SAMPLER
uniform sampler2D maskMapUnit;
uniform vec4 uMaskUnitCoords;
uniform float uMaskPercent;
#endif

#ifdef WITH_MATERIAL_AMBIENT
uniform vec4 uMaterialAmbient;
#endif
#ifdef WITH_MATERIAL_EMISSION
uniform vec4 uMaterialEmission;
#endif
#ifdef WITH_MATERIAL_DIFFUSE
uniform vec4 uMaterialDiffuse;
#endif
#ifdef WITH_MATERIAL_SPECULAR
uniform vec4 uMaterialSpecular;
#endif
#ifdef WITH_MATERIAL_SHININESS
uniform float uMaterialShininess;
#endif
uniform float uMaterialTransparency;

#ifdef WITH_RIM_LIGHT
uniform float uRimDensity;
uniform vec4 uRimColor;
#endif

#ifdef WITH_LIGHT_0
uniform vec4 uLightPosition0;
uniform float uLightAmbient0;
uniform float uLightDiffuse0;
uniform float uLightSpecular0;
uniform float uLightConstant0;
uniform float uLightLinear0;
uniform float uLightQuadratic0;
uniform float uAttenuation0;
uniform vec4 uLightColor0;
#endif
#ifdef WITH_LIGHT_1
uniform vec4 uLightPosition1;
uniform float uLightAmbient1;
uniform float uLightDiffuse1;
uniform float uLightSpecular1;
uniform float uLightConstant1;
uniform float uLightLinear1;
uniform float uLightQuadratic1;
uniform float uAttenuation1;
uniform vec4 uLightColor1;
#endif
#ifdef WITH_LIGHT_2
uniform vec4 uLightPosition2;
uniform float uLightAmbient2;
uniform float uLightDiffuse2;
uniform float uLightSpecular2;
uniform float uLightConstant2;
uniform float uLightLinear2;
uniform float uLightQuadratic2;
uniform float uAttenuation2;
uniform vec4 uLightColor2;
#endif
#ifdef WITH_LIGHT_3
uniform vec4 uLightPosition3;
uniform float uLightAmbient3;
uniform float uLightDiffuse3;
uniform float uLightSpecular3;
uniform float uLightConstant3;
uniform float uLightLinear3;
uniform float uLightQuadratic3;
uniform float uAttenuation3;
uniform vec4 uLightColor3;
#endif
#ifdef WITH_LIGHT_4
uniform vec4 uLightPosition4;
uniform float uLightAmbient4;
uniform float uLightDiffuse4;
uniform float uLightSpecular4;
uniform float uLightConstant4;
uniform float uLightLinear4;
uniform float uLightQuadratic4;
uniform float uAttenuation4;
uniform vec4 uLightColor4;
#endif
#ifdef WITH_LIGHT_5
uniform vec4 uLightPosition5;
uniform float uLightAmbient5;
uniform float uLightDiffuse5;
uniform float uLightSpecular5;
uniform float uLightConstant5;
uniform float uLightLinear5;
uniform float uLightQuadratic5;
uniform float uAttenuation5;
uniform vec4 uLightColor5;
#endif
#ifdef WITH_LIGHT_6
uniform vec4 uLightPosition6;
uniform float uLightAmbient6;
uniform float uLightDiffuse6;
uniform float uLightSpecular6;
uniform float uLightConstant6;
uniform float uLightLinear6;
uniform float uLightQuadratic6;
uniform float uAttenuation6;
uniform vec4 uLightColor6;
#endif
#ifdef WITH_LIGHT_7
uniform vec4 uLightPosition7;
uniform float uLightAmbient7;
uniform float uLightDiffuse7;
uniform float uLightSpecular7;
uniform float uLightConstant7;
uniform float uLightLinear7;
uniform float uLightQuadratic7;
uniform float uAttenuation7;
uniform vec4 uLightColor7;
#endif

uniform vec4 uCamPosition;

const float mipBias = -1000.0;

mat3 cotangent_frame( vec3 N, vec3 p, vec2 uv ) {
    vec3 dp1 = vec3(dFdx(p.x),dFdx(p.y),dFdx(p.z));
    vec3 dp2 = vec3(dFdy(p.x),dFdy(p.y),dFdy(p.z));
    vec2 duv1 = vec2(dFdx(uv.x),dFdx(uv.y));
    vec2 duv2 = vec2(dFdy(uv.x),dFdy(uv.y));
    #ifdef GL_ES
        highp vec3 dp2perp = cross( dp2, N );
        highp vec3 dp1perp = cross( N, dp1 );
        highp vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
        highp vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
    #else
        vec3 dp2perp = cross( dp2, N );
        vec3 dp1perp = cross( N, dp1 );
        vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
        vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
    #endif
    float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
    return mat3( T * invmax, B * invmax, N );
}

#ifdef WITH_NORMAL_SAMPLER
    #define WITH_NORMALMAP_UNSIGNED
    vec3 perturb_normal( vec3 N, vec3 V, vec2 texcoord ){
        vec3 map = texture2D(normalMapUnit, texcoord, mipBias).xyz * uNormalPercent;
    #ifdef WITH_NORMALMAP_UNSIGNED
        map = map * 255.0/127.0 - 128.0/127.0;
    #endif
    #ifdef WITH_NORMALMAP_2CHANNEL
        map.z = sqrt(1.0 - dot( map.xy, map.xy ) );
    #endif
    #ifdef WITH_NORMALMAP_GREEN_UP
        map.y = -map.y;
    #endif
        mat3 TBN = cotangent_frame( N, -V, texcoord );
        return normalize( TBN * map );
    }
#endif

float computeAmbient(float lAmb) {
    float result = 1.0;
    #ifdef WITH_LIGHT_AMBIENT
        result *= lAmb;
    #endif
    return result;
}

float computeDiffuse(float lDif, float lAttenuation, vec3 L, vec3 normal) {
    float result = 1.0;
    #ifdef WITH_GLOSS_SAMPLER
        vec2  roughnessV = texture2D(glossMapUnit, uGlossUnitCoords.xy + (uGlossUnitCoords.zw - uGlossUnitCoords.xy) * vTexCoord, mipBias).rg * uGlossPercent;
        result *= max(dot(normal, L), roughnessV.r);
    #else
        result *= max(dot(normal, L), 0.0);
    #endif
    #ifdef WITH_LIGHT_DIFFUSE
        result *= lDif;
    #endif
    result *= lAttenuation;
    return result;
}

float computeSpecular(float lSpec, float lAttenuation, float mShin, vec3 R, vec3 E) {
    float result = 1.0;
    #ifdef WITH_SPECULAR_SAMPLER
        float specularity = texture2D(specularMapUnit, uSpecularUnitCoords.xy + (uSpecularUnitCoords.zw - uSpecularUnitCoords.xy) * vTexCoord, mipBias).r * 255.0;
    #else
        float specularity = mShin;
    #endif
    #ifdef WITH_LIGHT_SPECULAR
        result *= lSpec;
    #endif
    result = pow(max(dot(R, E), 0.0), specularity);
    result *= lAttenuation;
    return result;
}

float computeAttenuation(float lConst, float lLin, float lQuad, float distance) {
    return 1.0 / (lConst + lLin * distance + lQuad * (distance * distance));
}

float sRGB(float c) {
    const float a = 0.055;
    if(c < 0.0031308) { return 12.92*c; }
    else { return (1.0+a)*pow(c, 1.0/2.2) - a; }
}

vec3 toSRGB(vec3 c) {
    return vec3(sRGB(c.x),sRGB(c.y),sRGB(c.z));
}

vec3 computeNormal() {
    #ifdef WITH_V_TANGENT
        #ifdef WITH_NORMAL_SAMPLER
            mat3 TBN = mat3(vTangent, vBinormal, vNormal);
            vec2 normalTexcoord = vec2(uNormalUnitCoords.xy + (uNormalUnitCoords.zw - uNormalUnitCoords.xy) * vTexCoord);
            vec3 bumpNormal = vec4(texture2D(normalMapUnit, normalTexcoord, mipBias)).xyz * 255.0/127.0 - 128.0/127.0 * uNormalPercent;
            vec3 normal = TBN * bumpNormal;
            #ifdef WITH_NORMALMAP_TO_SRGB
                normal = toSRGB(normal);
            #endif
            normal = normalize(normal);
        #else
            vec3 normal = normalize(vNormal);
        #endif
    #else
        #ifdef WITH_V_NORMAL
            vec3 normal = normalize(vNormal);

            #ifdef WITH_NORMAL_SAMPLER
                #ifdef WITH_TBN_FROM_NORMALS
                    normal = perturb_normal(normal, vPosition, uNormalUnitCoords.xy + (uNormalUnitCoords.zw - uNormalUnitCoords.xy) * vTexCoord);
                #endif
            #endif
        #endif
    #endif
    return normal;
}

vec4 computeTexel() {
    #ifdef WITH_MASK_SAMPLER
        float mask = texture2D(maskMapUnit, uMaskUnitCoords.xy + (uMaskUnitCoords.zw - uMaskUnitCoords.xy) * vTexCoord, mipBias).a * uMaskPercent;
        if ( mask < 0.001 ) {
            discard;
        }
    #endif

    vec4 texel = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 emission = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 ambient = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 diffuse = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 specular = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 reflection = vec4(0.0, 0.0, 0.0, 0.0);

    #ifdef WITH_MATERIAL_EMISSION
        emission = uMaterialEmission;
    #endif
    #ifdef WITH_MATERIAL_AMBIENT
        ambient = uMaterialAmbient;
    #endif

    #ifdef WITH_MATERIAL_DIFFUSE
        #ifdef WITH_AMBIENT_SAMPLER
            vec4 diffTextureTexel = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * vTexCoord, mipBias) * uTexUnitPercent;
            diffTextureTexel *= uMaterialDiffuse;
            diffuse = diffTextureTexel;
        #else
            diffuse = uMaterialDiffuse;
        #endif
    #endif

    #ifdef WITH_MATERIAL_SPECULAR
        specular = uMaterialSpecular;
    #endif

    #ifdef WITH_V_POSITION
        vec3 normal = computeNormal();

        #ifdef WITH_REFLECTION_SAMPLER
            float reflCoef = uReflectionPercent;
            //#ifdef WITH_SPECULAR_SAMPLER
            //    reflCoef += clamp(texSpec, 0.0, 1.0);
            //#endif
            vec3 r = reflect( normalize(-vPosition.xyz), normal );
            float m = 2.0 * sqrt( r.x*r.x + r.y*r.y + (r.z+1.0)*(r.z+1.0) );
            vec2 vReflCoord = vec2(r.x/m + 0.5, r.y/m + 0.5);
            vec4 reflectColor = texture2D(reflectMapUnit, uReflectUnitCoords.xy + (uReflectUnitCoords.zw - uReflectUnitCoords.xy) * vReflCoord, mipBias) * reflCoef;
            reflection = reflectColor;
        #endif

        #ifdef WITH_MATCAP_SAMPLER
            // vec3 bivector = uMatcapCameraPosition.xyz - vPosition.xyz;
            vec3 bivector = -vPosition.xyz;
            vec3 L = normalize(bivector);
            vec3 reflected = normalize(-reflect(L, normal));
            float m = 2.0 * sqrt( pow(reflected.x, 2.0) + pow(reflected.y, 2.0) + pow(reflected.z + 1.0, 2.0) );
            vec2 uv = reflected.xy / m + 0.5;
            uv = vec2(uv.x, 1.0 - uv.y);

            vec4 matcap = vec4(texture2D(matcapUnit, uMatcapUnitCoords.xy + (uMatcapUnitCoords.zw - uMatcapUnitCoords.xy) * uv, mipBias).rgb, uMaterialTransparency) * uMatcapPercent;

            #ifdef WITH_MATCAP_INTERPOLATE_SAMPLER
                vec4 matcapInter = vec4(texture2D(matcapUnitInterpolate, uMatcapUnitCoordsInterpolate.xy + (uMatcapUnitCoordsInterpolate.zw - uMatcapUnitCoordsInterpolate.xy) * uv, mipBias).rgb, uMaterialTransparency) * uMatcapPercentInterpolate;
                matcap = mix(matcap, matcapInter, uMatcapMixPercent);
            #endif

            diffuse += matcap;
        #else
            #ifdef WITH_LIGHT_POSITION

                vec3 lightAmbient = vec3(0.0,0.0,0.0);
                vec3 lightDiffuse = vec3(0.0,0.0,0.0);
                vec3 lightSpecular = vec3(0.0,0.0,0.0);

                vec3 bivector = vec3(0.0,0.0,0.0);
                vec3 E = normalize(-vPosition.xyz);
                vec3 L = vec3(0.0,0.0,0.0);
                vec3 R = vec3(0.0,0.0,0.0);
                float distance = 0.0;
                float attenuation = 1.0;
                float specularity = 0.0;

                #ifdef WITH_SPECULAR_SAMPLER
                    specularity = texture2D(specularMapUnit, uSpecularUnitCoords.xy + (uSpecularUnitCoords.zw - uSpecularUnitCoords.xy) * vTexCoord, mipBias).r * uSpecularPercent;
                #endif

                #ifdef WITH_LIGHT_0
                    bivector = uLightPosition0.xyz - vPosition.xyz;
                    L = normalize(bivector);
                    R = normalize(-reflect(L, normal));
                    distance = length(bivector);
                    attenuation = 1.0;
                    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                        attenuation = uAttenuation0;
                    #endif
                    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                        attenuation = computeAttenuation(uLightConstant0, uLightLinear0, uLightQuadratic0, distance);
                    #endif
                    lightAmbient += uLightColor0.rgb*computeAmbient(uLightAmbient0);
                    lightDiffuse += uLightColor0.rgb*computeDiffuse(uLightDiffuse0, attenuation, L, normal);
                    #ifdef WITH_MATERIAL_SHININESS
                        lightSpecular += uLightColor0.rgb*computeSpecular(uLightSpecular0, attenuation, specularity+uMaterialShininess, R, E);
                    #endif
                #endif
                #ifdef WITH_LIGHT_1
                    bivector = uLightPosition1.xyz - vPosition.xyz;
                    L = normalize(bivector);
                    R = normalize(-reflect(L, normal));
                    distance = length(bivector);
                    attenuation = 1.0;
                    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                        attenuation = uAttenuation1;
                    #endif
                    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                        attenuation = computeAttenuation(uLightConstant1, uLightLinear1, uLightQuadratic1, distance);
                    #endif
                    lightAmbient += uLightColor1.rgb*computeAmbient(uLightAmbient1);
                    lightDiffuse += uLightColor1.rgb*computeDiffuse(uLightDiffuse1, attenuation, L, normal);
                    #ifdef WITH_MATERIAL_SHININESS
                        lightSpecular += uLightColor1.rgb*computeSpecular(uLightSpecular1, attenuation, specularity+uMaterialShininess, R, E);
                    #endif
                #endif
                #ifdef WITH_LIGHT_2
                    bivector = uLightPosition2.xyz - vPosition.xyz;
                    L = normalize(bivector);
                    R = normalize(-reflect(L, normal));
                    distance = length(bivector);
                    attenuation = 1.0;
                    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                        attenuation = uAttenuation2;
                    #endif
                    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                        attenuation = computeAttenuation(uLightConstant2, uLightLinear2, uLightQuadratic2, distance);
                    #endif
                    lightAmbient += uLightColor2.rgb*computeAmbient(uLightAmbient2);
                    lightDiffuse += uLightColor2.rgb*computeDiffuse(uLightDiffuse2, attenuation, L, normal);
                    #ifdef WITH_MATERIAL_SHININESS
                        lightSpecular += uLightColor2.rgb*computeSpecular(uLightSpecular2, attenuation, specularity+uMaterialShininess, R, E);
                    #endif
                #endif
                #ifdef WITH_LIGHT_3
                    bivector = uLightPosition3.xyz - vPosition.xyz;
                    L = normalize(bivector);
                    R = normalize(-reflect(L, normal));
                    distance = length(bivector);
                    attenuation = 1.0;
                    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                        attenuation = uAttenuation3;
                    #endif
                    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                        attenuation = computeAttenuation(uLightConstant3, uLightLinear3, uLightQuadratic3, distance);
                    #endif
                    lightAmbient += uLightColor3.rgb*computeAmbient(uLightAmbient3);
                    lightDiffuse += uLightColor3.rgb*computeDiffuse(uLightDiffuse3, attenuation, L, normal);
                    #ifdef WITH_MATERIAL_SHININESS
                        lightSpecular += uLightColor3.rgb*computeSpecular(uLightSpecular3, attenuation, specularity+uMaterialShininess, R, E);
                    #endif
                #endif
                #ifdef WITH_LIGHT_4
                    bivector = uLightPosition4.xyz - vPosition.xyz;
                    L = normalize(bivector);
                    R = normalize(-reflect(L, normal));
                    distance = length(bivector);
                    attenuation = 1.0;
                    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                        attenuation = uAttenuation4;
                    #endif
                    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                        attenuation = computeAttenuation(uLightConstant4, uLightLinear4, uLightQuadratic4, distance);
                    #endif
                    lightAmbient += uLightColor4.rgb*computeAmbient(uLightAmbient4);
                    lightDiffuse += uLightColor4.rgb*computeDiffuse(uLightDiffuse4, attenuation, L, normal);
                    #ifdef WITH_MATERIAL_SHININESS
                        lightSpecular += uLightColor4.rgb*computeSpecular(uLightSpecular4, attenuation, specularity+uMaterialShininess, R, E);
                    #endif
                #endif
                #ifdef WITH_LIGHT_5
                    bivector = uLightPosition5.xyz - vPosition.xyz;
                    L = normalize(bivector);
                    R = normalize(-reflect(L, normal));
                    distance = length(bivector);
                    attenuation = 1.0;
                    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                        attenuation = uAttenuation5;
                    #endif
                    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                        attenuation = computeAttenuation(uLightConstant5, uLightLinear5, uLightQuadratic5, distance);
                    #endif
                    lightAmbient += uLightColor5.rgb*computeAmbient(uLightAmbient5);
                    lightDiffuse += uLightColor5.rgb*computeDiffuse(uLightDiffuse5, attenuation, L, normal);
                    #ifdef WITH_MATERIAL_SHININESS
                        lightSpecular += uLightColor5.rgb*computeSpecular(uLightSpecular5, attenuation, specularity+uMaterialShininess, R, E);
                    #endif
                #endif
                #ifdef WITH_LIGHT_6
                    bivector = uLightPosition6.xyz - vPosition.xyz;
                    L = normalize(bivector);
                    R = normalize(-reflect(L, normal));
                    distance = length(bivector);
                    attenuation = 1.0;
                    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                        attenuation = uAttenuation6;
                    #endif
                    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                        attenuation = computeAttenuation(uLightConstant6, uLightLinear6, uLightQuadratic6, distance);
                    #endif
                    lightAmbient += uLightColor6.rgb*computeAmbient(uLightAmbient6);
                    lightDiffuse += uLightColor6.rgb*computeDiffuse(uLightDiffuse6, attenuation, L, normal);
                    #ifdef WITH_MATERIAL_SHININESS
                        lightSpecular += uLightColor6.rgb*computeSpecular(uLightSpecular6, attenuation, specularity+uMaterialShininess, R, E);
                    #endif
                #endif
                #ifdef WITH_LIGHT_7
                    bivector = uLightPosition7.xyz - vPosition.xyz;
                    L = normalize(bivector);
                    R = normalize(-reflect(L, normal));
                    distance = length(bivector);
                    attenuation = 1.0;
                    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                        attenuation = uAttenuation7;
                    #endif
                    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                        attenuation = computeAttenuation(uLightConstant7, uLightLinear7, uLightQuadratic7, distance);
                    #endif
                    lightAmbient += uLightColor7.rgb*computeAmbient(uLightAmbient7);
                    lightDiffuse += uLightColor7.rgb*computeDiffuse(uLightDiffuse7, attenuation, L, normal);
                    #ifdef WITH_MATERIAL_SHININESS
                        lightSpecular += uLightColor7.rgb*computeSpecular(uLightSpecular7, attenuation, specularity+uMaterialShininess, R, E);
                    #endif
                #endif

                ambient.rgb *= lightAmbient;
                diffuse.rgb *= lightDiffuse;
                specular.rgb *= lightSpecular;
            #endif
        #endif

        #ifdef WITH_RIM_LIGHT
           float vdn = 1.0 - max(dot(normalize(-vPosition), normal), 0.0);
           vec4 rim = vec4(smoothstep(uRimDensity, 1.0, vdn));
           texel += rim * uRimColor;
        #endif
    #endif

    texel += max(ambient*ambient.a, diffuse);
    texel += specular*specular.a;
    texel += emission*emission.a;
    texel += reflection*reflection.a;

    texel.a *= uMaterialTransparency;

    #ifdef WITH_AMBIENT_SAMPLER
        texel.a *= diffuse.a;
    #endif

    #ifdef WITH_GAMMA_CORRECTION
        vec3 gamma = vec3(1.0/2.2);
        texel = vec4(pow(texel.xyz, gamma), texel.a);
    #endif

    return texel;
}

void main() {
    gl_FragColor = computeTexel();
}
"""
