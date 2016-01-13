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
uniform mat4 modelMatrix;
uniform mat3 normalMatrix;

void main() {
#ifdef WITH_V_POSITION
    vPosition = vec4(modelMatrix * aPosition).xyz;
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

#ifdef WITH_MATERIAL_DIFFUSE
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
    vec3 map = texture2D(normalMapUnit, texcoord).xyz;
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

vec3 computePointLight(vec3 texel, vec3 normal, vec3 pos, vec3 lPos,
                        float lAmb, float lDif, float lSpec, float lConst, float lLin, float lQuad, float lAtt,
                        vec3 mAmb, vec3 mDif, vec3 mSpec, float mShin) {

    vec3 bivector = lPos - pos;

    float specularity = 1.0;

    #ifdef WITH_MATERIAL_SHININESS
        specularity = mShin;
    #endif

    float attenuation = 1.0;

    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
        attenuation = lAtt;
    #else
        #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
            float distance = length(bivector);
            attenuation = 1.0 / (lConst + lLin * distance + lQuad * (distance * distance));
        #endif
    #endif

    #ifdef WITH_GLOSS_SAMPLER
        vec2  roughnessV = texture2D(glossMapUnit, uGlossUnitCoords.xy + (uGlossUnitCoords.zw - uGlossUnitCoords.xy) * vTexCoord).rg;
        float roughness = (1-roughnessV.r) + uMaterialDiffuse.z * (1.0 - roughnessV.g);
    #endif
    #ifdef WITH_SPECULAR_SAMPLER
        specularity = texture2D(specularMapUnit, uSpecularUnitCoords.xy + (uSpecularUnitCoords.zw - uSpecularUnitCoords.xy) * vTexCoord).r * 255.0;
    #endif

    vec3 L = normalize(bivector);
    vec3 E = normalize(-pos);
    vec3 R = normalize(-reflect(L, normal));

    vec3 ambient = texel;
    #ifdef WITH_LIGHT_AMBIENT
        ambient *= lAmb;
    #endif

    vec3 diffuse = texel;
    #ifdef WITH_MATERIAL_DIFFUSE
       diffuse += mDif;
    #endif
    #ifdef WITH_LIGHT_DIFFUSE
        diffuse *= lDif;
    #endif
    #ifdef WITH_GLOSS_SAMPLER
        diffuse *= roughness;
    #endif

    diffuse *= max(dot(normal, L), 0.0);
    diffuse *= attenuation;

    vec3 specular = texel;
    #ifdef WITH_MATERIAL_SPECULAR
        specular += mSpec;
    #endif
    #ifdef WITH_LIGHT_SPECULAR
        specular *= lSpec;
    #endif
    #ifdef WITH_GLOSS_SAMPLER
        specular *= roughness;
    #endif

    specular *= pow(max(dot(R, E), 0.0), specularity);
    specular *= attenuation;

    texel = clamp((ambient + diffuse + specular), 0.0, 1.0);


    #ifdef WITH_REFLECTION_SAMPLER
        vec3 r = reflect( -pos, normal );
        float m = 2.0 * sqrt( r.x*r.x + r.y*r.y + (r.z+1.0)*(r.z+1.0) );
        vec2 vReflCoord = vec2(r.x/m + 0.5, r.y/m + 0.5);
        vec3 reflectColor = texture2D(reflectMapUnit, uReflectUnitCoords.xy + (uReflectUnitCoords.zw - uReflectUnitCoords.xy) * vReflCoord).xyz * uReflectivity;

        #ifdef WITH_FALLOF_SAMPLER
            float rampPercent = 0.05;

            vec2 rampTexCoord = uFallofUnitCoords.xy + (uFallofUnitCoords.zw - uFallofUnitCoords.xy);
            float rampR = texture2D(falloffMapUnit, rampTexCoord * vec2((1.0-reflectColor.r+rampPercent), 0)).r;
            float rampG = texture2D(falloffMapUnit, rampTexCoord * vec2((1.0-reflectColor.g+rampPercent), 0)).g;
            float rampB = texture2D(falloffMapUnit, rampTexCoord * vec2((1.0-reflectColor.b+rampPercent), 0)).b;

            reflectColor = vec3(rampR, rampG, rampB);
        #endif

        texel += reflectColor;
    #endif

    return texel;
}

vec4 computeTexel() {
    vec4 texel = vec4(0.0, 0.0, 0.0, 0.0);

    #ifdef WITH_MATERIAL_EMISSION
        texel += uMaterialEmission;
    #endif

    #ifdef WITH_MATERIAL_AMBIENT
       texel += uMaterialAmbient;
    #endif

    #ifdef WITH_AMBIENT_SAMPLER
        texel += texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * vTexCoord);
    #endif

    #ifdef WITH_V_POSITION
        #ifdef WITH_V_TANGENT
            mat3 TBN = mat3(vTangent, vBinormal, vNormal);
            vec2 normalTexcoord = vec2(uNormalUnitCoords.xy + (uNormalUnitCoords.zw - uNormalUnitCoords.xy) * vTexCoord);
            vec3 bumpNormal = vec4(texture2D(normalMapUnit, normalTexcoord)).xyz * 255.0/127.0 - 128.0/127.0;
            vec3 normal = TBN * bumpNormal;
            normal = normalize(normal);
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

        #ifdef WITH_RIM_LIGHT
            float vdn = 1.0 - max(dot(normalize(-vPosition), normal), 0.0);
            vec4 rim = vec4(smoothstep(0.0, 1.0, vdn));
            texel += rim;
        #endif

        #ifdef WITH_LIGHT_POSITION
            #ifdef WITH_LIGHT_0
            texel = vec4(computePointLight(texel.xyz, normal, vPosition.xyz, uLightPosition0.xyz,
                                            uLightAmbient0, uLightDiffuse0, uLightSpecular0, uLightConstant0, uLightLinear0, uLightQuadratic0, uAttenuation0,
                                            uMaterialAmbient.xyz, uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), texel.w);
            #endif
            #ifdef WITH_LIGHT_1
            texel = vec4(computePointLight(texel.xyz, normal, vPosition.xyz, uLightPosition1.xyz,
                                            uLightAmbient1, uLightDiffuse1, uLightSpecular1, uLightConstant1, uLightLinear1, uLightQuadratic1, uAttenuation1,
                                            uMaterialAmbient.xyz, uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), texel.w);
            #endif
            #ifdef WITH_LIGHT_2
            texel = vec4(computePointLight(texel.xyz, normal, vPosition.xyz, uLightPosition2.xyz,
                                            uLightAmbient2, uLightDiffuse2, uLightSpecular2, uLightConstant2, uLightLinear2, uLightQuadratic2, uAttenuation2,
                                            uMaterialAmbient.xyz, uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), texel.w);
            #endif
            #ifdef WITH_LIGHT_3
            texel = vec4(computePointLight(texel.xyz, normal, vPosition.xyz, uLightPosition3.xyz,
                                            uLightAmbient3, uLightDiffuse3, uLightSpecular3, uLightConstant3, uLightLinear3, uLightQuadratic3, uAttenuation3,
                                            uMaterialAmbient.xyz, uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), texel.w);
            #endif
            #ifdef WITH_LIGHT_4
            texel = vec4(computePointLight(texel.xyz, normal, vPosition.xyz, uLightPosition4.xyz,
                                            uLightAmbient4, uLightDiffuse4, uLightSpecular4, uLightConstant4, uLightLinear4, uLightQuadratic4, uAttenuation4,
                                            uMaterialAmbient.xyz, uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), texel.w);
            #endif
            #ifdef WITH_LIGHT_5
            texel = vec4(computePointLight(texel.xyz, normal, vPosition.xyz, uLightPosition5.xyz,
                                            uLightAmbient5, uLightDiffuse5, uLightSpecular5, uLightConstant5, uLightLinear5, uLightQuadratic5, uAttenuation5,
                                            uMaterialAmbient.xyz, uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), texel.w);
            #endif
            #ifdef WITH_LIGHT_6
            texel = vec4(computePointLight(texel.xyz, normal, vPosition.xyz, uLightPosition6.xyz,
                                            uLightAmbient6, uLightDiffuse6, uLightSpecular6, uLightConstant6, uLightLinear6, uLightQuadratic6, uAttenuation6,
                                            uMaterialAmbient.xyz, uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), texel.w);
            #endif
            #ifdef WITH_LIGHT_7
            texel = vec4(computePointLight(texel.xyz, normal, vPosition.xyz, uLightPosition7.xyz,
                                            uLightAmbient7, uLightDiffuse7, uLightSpecular7, uLightConstant7, uLightLinear7, uLightQuadratic7, uAttenuation7,
                                            uMaterialAmbient.xyz, uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), texel.w);
            #endif

            // #ifdef WITH_REFLECTION_SAMPLER
            //     vec3 r = -reflect( vPosition.xyz, normal.xyz );
            //     float m = 2.0 * sqrt( r.x*r.x + r.y*r.y + (r.z+1.0)*(r.z+1.0) );
            //     vec2 vReflCoord= vec2(r.x/m + 0.5, r.y/m + 0.5);
            //     texel += texture2D(reflectMapUnit, uReflectUnitCoords.xy + (uReflectUnitCoords.zw - uReflectUnitCoords.xy) * vReflCoord) * uReflectivity;
            // #endif
        #endif
    #endif

    return texel;
}

void main() {
    gl_FragColor = computeTexel();

    // vec3 gamma = vec3(1.0/2.2);
    // vec4 linearColor = computeTexel();
    // gl_FragColor = vec4(pow(linearColor.rgb, gamma), linearColor.a);
}
"""
