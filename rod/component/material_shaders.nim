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

#ifdef WITH_AMBIENT_SAMPLER
uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
#endif
#ifdef WITH_GLOSS_SAMPLER
uniform sampler2D glossMapUnit;
uniform vec4 uGlossUnitCoords;
#endif
#ifdef WITH_SPECULAR_SAMPLER
uniform sampler2D specularMapUnit;
uniform vec4 uSpecularUnitCoords;
#endif
#ifdef WITH_BUMP_SAMPLER
uniform sampler2D bumpMapUnit;
uniform vec4 uBumpUnitCoords;
#endif
#ifdef WITH_NORMAL_SAMPLER
uniform sampler2D normalMapUnit;
uniform vec4 uNormalUnitCoords;
#endif
#ifdef WITH_REFLECTION_SAMPLER
uniform sampler2D reflectMapUnit;
uniform vec4 uReflectUnitCoords;
uniform float uReflectivity;
#endif
#ifdef WITH_FALLOF_SAMPLER
uniform sampler2D falloffMapUnit;
uniform vec4 uFallofUnitCoords;
#endif
#ifdef WITH_MASK_SAMPLER
uniform sampler2D maskMapUnit;
uniform vec4 uMaskUnitCoords;
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
#endif
// uniform vec4 uCamPosition;

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
        vec3 map = texture2D(normalMapUnit, texcoord, mipBias).xyz;
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
        vec2  roughnessV = texture2D(glossMapUnit, uGlossUnitCoords.xy + (uGlossUnitCoords.zw - uGlossUnitCoords.xy) * vTexCoord, mipBias).rg;
        float roughness = (1-roughnessV.r) + uMaterialDiffuse.z * (1.0 - roughnessV.g);
        result *= roughness;
    #endif
    #ifdef WITH_LIGHT_DIFFUSE
        result *= lDif;
    #endif
    result *= max(dot(normal, L), 0.0);
    result *= lAttenuation;

    return result;
}


float computeSpecular(float lSpec, float lAttenuation, float mShin, vec3 R, vec3 E) {
    float result = 1.0;
    #ifdef WITH_SPECULAR_SAMPLER
        //float specularity = texture2D(specularMapUnit, uSpecularUnitCoords.xy + (uSpecularUnitCoords.zw - uSpecularUnitCoords.xy) * vTexCoord, mipBias).r * 255.0;
        float specularity = mShin;
    #else
        float specularity = mShin;
    #endif
    #ifdef WITH_LIGHT_SPECULAR
        result *= lSpec;
    #endif

    result *= pow(max(dot(R, E), 0.0), specularity);
    result *= lAttenuation;

    return result;
}

float computeAttenuation(float lConst, float lLin, float lQuad, float distance, float precompAttenuation) {
    float result = 1.0;
    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
        result = 1.0 / (lConst + lLin * distance + lQuad * (distance * distance));
    #else
        #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
            result = precompAttenuation;
        #endif
    #endif
    return result;
}

float sRGB(float c) {
    const float a = 0.055;
    if(c < 0.0031308) { return 12.92*c; }
    else { return (1.0+a)*pow(c, 1.0/2.2) - a; }
}

vec3 toSRGB(vec3 c) {
    return vec3(sRGB(c.x),sRGB(c.y),sRGB(c.z));
}

vec4 computeTexel() {
    #ifdef WITH_MASK_SAMPLER
        float mask = texture2D(maskMapUnit, uMaskUnitCoords.xy + (uMaskUnitCoords.zw - uMaskUnitCoords.xy) * vTexCoord, mipBias).a;
        if ( mask < 0.001 ) {
            discard;
        }
    #endif

    vec4 emission = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 ambient = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 diffuse = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 specular = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 reflection = vec4(0.0, 0.0, 0.0, 0.0);

    #ifdef WITH_MATERIAL_EMISSION
        emission += uMaterialEmission;
    #endif
    #ifdef WITH_MATERIAL_AMBIENT
        ambient += uMaterialAmbient;
    #endif

    #ifdef WITH_MATERIAL_DIFFUSE
        #ifdef WITH_AMBIENT_SAMPLER
            vec4 diffTextureTexel = texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * vTexCoord, mipBias);
            diffTextureTexel *= uMaterialDiffuse;
            diffuse += diffTextureTexel;
        #else
            diffuse += uMaterialDiffuse;
        #endif
    #endif
    #ifdef WITH_MATERIAL_SPECULAR
        specular += uMaterialSpecular;
    #endif

    #ifdef WITH_V_POSITION
        #ifdef WITH_V_TANGENT
            #ifdef WITH_NORMAL_SAMPLER
                mat3 TBN = mat3(vTangent, vBinormal, vNormal);
                vec2 normalTexcoord = vec2(uNormalUnitCoords.xy + (uNormalUnitCoords.zw - uNormalUnitCoords.xy) * vTexCoord);
                vec3 bumpNormal = vec4(texture2D(normalMapUnit, normalTexcoord, mipBias)).xyz * 255.0/127.0 - 128.0/127.0;

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

        float ambCoef = 1.0;
        float diffCoef = 1.0;
        float specCoef = 1.0;

        #ifdef WITH_SPECULAR_SAMPLER
            float texSpec = texture2D(specularMapUnit, uSpecularUnitCoords.xy + (uSpecularUnitCoords.zw - uSpecularUnitCoords.xy) * vTexCoord, mipBias).r;
            specCoef += texSpec;
        #endif

        #ifdef WITH_REFLECTION_SAMPLER
            float reflCoef = uReflectivity;

            #ifdef WITH_SPECULAR_SAMPLER
                reflCoef += clamp(texSpec, 0.0, 1.0);
            #endif

            vec3 r = reflect( normalize(-vPosition.xyz), normal );
            float m = 2.0 * sqrt( r.x*r.x + r.y*r.y + (r.z+1.0)*(r.z+1.0) );
            vec2 vReflCoord = vec2(r.x/m + 0.5, r.y/m + 0.5);
            vec4 reflectColor = texture2D(reflectMapUnit, uReflectUnitCoords.xy + (uReflectUnitCoords.zw - uReflectUnitCoords.xy) * vReflCoord, mipBias) * reflCoef;

            // ambient += reflectColor;

            reflection += reflectColor;

            // #ifdef WITH_FALLOF_SAMPLER
            //     float rampPercent = 0.0;

            //     vec2 rampTexCoord = uFallofUnitCoords.xy + (uFallofUnitCoords.zw - uFallofUnitCoords.xy);
            //     float rampR = texture2D(falloffMapUnit, rampTexCoord * vec2((1.0-ambient.r+rampPercent), 0)).r;
            //     float rampG = texture2D(falloffMapUnit, rampTexCoord * vec2((1.0-ambient.g+rampPercent), 0)).g;
            //     float rampB = texture2D(falloffMapUnit, rampTexCoord * vec2((1.0-ambient.b+rampPercent), 0)).b;

            //     ambient = vec4(rampR, rampG, rampB, ambient.w);
            // #endif
        #endif

        #ifdef WITH_LIGHT_POSITION
            ambCoef = 0.0;
            diffCoef = 0.0;
            specCoef = 0.0;

            vec3 E = normalize(-vPosition.xyz);

            #ifdef WITH_LIGHT_0
                vec3 bivector0 = uLightPosition0.xyz - vPosition.xyz;
                vec3 L0 = normalize(bivector0);
                vec3 R0 = normalize(-reflect(L0, normal));
                float distance0 = length(bivector0);
                float attenuation0 = computeAttenuation(uLightConstant0, uLightLinear0, uLightQuadratic0, distance0, uAttenuation0);
                ambCoef += computeAmbient(uLightAmbient0);
                diffCoef += computeDiffuse(uLightDiffuse0, attenuation0, L0, normal);
                #ifdef WITH_MATERIAL_SHININESS
                    specCoef += computeSpecular(uLightSpecular0, attenuation0, uMaterialShininess, R0, E);
                #endif
            #endif
            #ifdef WITH_LIGHT_1
                vec3 bivector1 = uLightPosition1.xyz - vPosition.xyz;
                vec3 L1 = normalize(bivector1);
                vec3 R1 = normalize(-reflect(L1, normal));
                float distance1 = length(bivector1);
                float attenuation1 = computeAttenuation(uLightConstant1, uLightLinear1, uLightQuadratic1, distance1, uAttenuation1);
                ambCoef += computeAmbient(uLightAmbient1);
                diffCoef += computeDiffuse(uLightDiffuse1, attenuation1, L1, normal);
                #ifdef WITH_MATERIAL_SHININESS
                    specCoef += computeSpecular(uLightSpecular1, attenuation1, uMaterialShininess, R1, E);
                #endif
            #endif
            #ifdef WITH_LIGHT_2
                vec3 bivector2 = uLightPosition2.xyz - vPosition.xyz;
                vec3 L2 = normalize(bivector2);
                vec3 R2 = normalize(-reflect(L2, normal));
                float distance2 = length(bivector2);
                float attenuation2 = computeAttenuation(uLightConstant2, uLightLinear2, uLightQuadratic2, distance2, uAttenuation2);
                ambCoef += computeAmbient(uLightAmbient2);
                diffCoef += computeDiffuse(uLightDiffuse2, attenuation2, L2, normal);
                #ifdef WITH_MATERIAL_SHININESS
                    specCoef += computeSpecular(uLightSpecular2, attenuation2, uMaterialShininess, R2, E);
                #endif
            #endif
            #ifdef WITH_LIGHT_3
                vec3 bivector3 = uLightPosition3.xyz - vPosition.xyz;
                vec3 L3 = normalize(bivector3);
                vec3 R3 = normalize(-reflect(L3, normal));
                float distance3 = length(bivector3);
                float attenuation3 = computeAttenuation(uLightConstant3, uLightLinear3, uLightQuadratic3, distance3, uAttenuation3);
                ambCoef += computeAmbient(uLightAmbient3);
                diffCoef += computeDiffuse(uLightDiffuse3, attenuation3, L3, normal);
                #ifdef WITH_MATERIAL_SHININESS
                    specCoef += computeSpecular(uLightSpecular3, attenuation3, uMaterialShininess, R3, E);
                #endif
            #endif
            #ifdef WITH_LIGHT_4
                vec3 bivector4 = uLightPosition4.xyz - vPosition.xyz;
                vec3 L4 = normalize(bivector4);
                vec3 R4 = normalize(-reflect(L4, normal));
                float distance4 = length(bivector4);
                float attenuation4 = computeAttenuation(uLightConstant4, uLightLinear4, uLightQuadratic4, distance4, uAttenuation4);
                ambCoef += computeAmbient(uLightAmbient4);
                diffCoef += computeDiffuse(uLightDiffuse4, attenuation4, L4, normal);
                #ifdef WITH_MATERIAL_SHININESS
                    specular += computeSpecular(uLightSpecular4, attenuation4, uMaterialShininess, R4, E);
                #endif
            #endif
            #ifdef WITH_LIGHT_5
                vec3 bivector5 = uLightPosition5.xyz - vPosition.xyz;
                vec3 L5 = normalize(bivector5);
                vec3 R5 = normalize(-reflect(L5, normal));
                float distance5 = length(bivector5);
                float attenuation5 = computeAttenuation(uLightConstant5, uLightLinear5, uLightQuadratic5, distance5, uAttenuation5);
                ambCoef += computeAmbient(uLightAmbient5);
                diffCoef += computeDiffuse(uLightDiffuse5, attenuation5, L5, normal);
                #ifdef WITH_MATERIAL_SHININESS
                    specCoef += computeSpecular(uLightSpecular5, attenuation5, uMaterialShininess, R5, E);
                #endif
            #endif
            #ifdef WITH_LIGHT_6
                vec3 bivector6 = uLightPosition6.xyz - vPosition.xyz;
                vec3 L6 = normalize(bivector6);
                vec3 R6 = normalize(-reflect(L6, normal));
                float distance6 = length(bivector6);
                float attenuation6 = computeAttenuation(uLightConstant6, uLightLinear6, uLightQuadratic6, distance6, uAttenuation6);
                ambCoef += computeAmbient(uLightAmbient6);
                diffCoef += computeDiffuse(uLightDiffuse6, attenuation6, L6, normal);
                #ifdef WITH_MATERIAL_SHININESS
                    specCoef += computeSpecular(uLightSpecular6, attenuation6, uMaterialShininess, R6, E);
                #endif
            #endif
            #ifdef WITH_LIGHT_7
                vec3 bivector7 = uLightPosition7.xyz - vPosition.xyz;
                vec3 L7 = normalize(bivector7);
                vec3 R7 = normalize(-reflect(L7, normal));
                float distance7 = length(bivector7);
                float attenuation7 = computeAttenuation(uLightConstant7, uLightLinear7, uLightQuadratic7, distance7, uAttenuation7);
                ambCoef += computeAmbient(uLightAmbient7);
                diffCoef += computeDiffuse(uLightDiffuse7, attenuation7, L7, normal);
                #ifdef WITH_MATERIAL_SHININESS
                    specCoef += computeSpecular(uLightSpecular7, attenuation7, uMaterialShininess, R7, E);
                #endif
            #endif
        #endif

        vec4 texel = emission + ambient*ambCoef + diffuse*diffCoef + specular*specCoef + reflection;

        #ifdef WITH_RIM_LIGHT
           float vdn = 1.0 - max(dot(normalize(-vPosition), normal), 0.0);
           vec4 rim = vec4(smoothstep(uRimDensity, 1.0, vdn));
           // texel += rim * diffCoef;
           texel += rim;
        #endif
    #else
        vec4 texel = emission + ambient + diffuse + specular + reflection;
    #endif

    texel.a = diffuse.a;
    texel.a *= uMaterialTransparency;

    return texel;
}

void main() {
    gl_FragColor = computeTexel();
}
"""
