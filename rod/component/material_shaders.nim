const materialVertexShaderDefault* = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;
attribute vec4 aNormal;
attribute vec4 aTangent;
attribute vec4 aBinormal;

uniform mat4 modelViewProjectionMatrix;
uniform mat4 modelMatrix;
uniform mat3 normalMatrix;

varying vec3 vPosition;
varying vec3 vNormal;
varying vec3 vBinormal;
varying vec3 vTangent;
varying vec2 vTexCoord;
varying vec2 vReflCoord;

void main() {
#ifdef WITH_V_POSITION
    vPosition = vec4(modelMatrix * aPosition).xyz;
#endif
#ifdef WITH_V_NORMAL
    vNormal = normalize(normalMatrix * aNormal.xyz);
#endif
#ifdef WITH_V_BINORMAL
    vBinormal = normalize(normalMatrix * aBinormal.xyz);
#endif
#ifdef WITH_V_TANGENT
    vTangent = normalize(normalMatrix * aTangent.xyz);
#endif
#ifdef WITH_V_TEXCOORD
    vTexCoord = aTexCoord;
#endif
#ifdef WITH_REFLECTION_SAMPLER
    vec3 r = -reflect( vPosition.xyz, vNormal.xyz );
    float m = 2.0 * sqrt( r.x*r.x + r.y*r.y + (r.z+1.0)*(r.z+1.0) );
    vReflCoord= vec2(r.x/m + 0.5, r.y/m + 0.5);
#endif

    gl_Position = modelViewProjectionMatrix * vec4(aPosition.xyz, 1.0);
}
"""
const materialFragmentShaderDefault* = """
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D texUnit;
uniform vec4 uTexUnitCoords;
uniform sampler2D glossMapUnit;
uniform vec4 uGlossUnitCoords;
uniform sampler2D specularMapUnit;
uniform vec4 uSpecularUnitCoords;
uniform sampler2D bumpMapUnit;
uniform vec4 uBumpUnitCoords;
uniform sampler2D normalMapUnit;
uniform vec4 uNormalUnitCoords;
uniform sampler2D reflectMapUnit;
uniform vec4 uReflectUnitCoords;
uniform sampler2D uMaterialFallof;
uniform vec4 uFallofUnitCoords;

uniform vec4 uMaterialAmbient;
uniform vec4 uMaterialDiffuse;
uniform vec4 uMaterialSpecular;
uniform float uMaterialShininess;

uniform vec4 uLightPosition0;
uniform float uLightAmbient0;
uniform float uLightDiffuse0;
uniform float uLightSpecular0;
uniform float uLightConstant0;
uniform float uLightLinear0;
uniform float uLightQuadratic0;
uniform float uAttenuation0;

uniform vec4 uLightPosition1;
uniform float uLightAmbient1;
uniform float uLightDiffuse1;
uniform float uLightSpecular1;
uniform float uLightConstant1;
uniform float uLightLinear1;
uniform float uLightQuadratic1;
uniform float uAttenuation1;

uniform vec4 uLightPosition2;
uniform float uLightAmbient2;
uniform float uLightDiffuse2;
uniform float uLightSpecular2;
uniform float uLightConstant2;
uniform float uLightLinear2;
uniform float uLightQuadratic2;
uniform float uAttenuation2;

uniform vec4 uLightPosition3;
uniform float uLightAmbient3;
uniform float uLightDiffuse3;
uniform float uLightSpecular3;
uniform float uLightConstant3;
uniform float uLightLinear3;
uniform float uLightQuadratic3;
uniform float uAttenuation3;

uniform vec4 uLightPosition4;
uniform float uLightAmbient4;
uniform float uLightDiffuse4;
uniform float uLightSpecular4;
uniform float uLightConstant4;
uniform float uLightLinear4;
uniform float uLightQuadratic4;
uniform float uAttenuation4;

uniform vec4 uLightPosition5;
uniform float uLightAmbient5;
uniform float uLightDiffuse5;
uniform float uLightSpecular5;
uniform float uLightConstant5;
uniform float uLightLinear5;
uniform float uLightQuadratic5;
uniform float uAttenuation5;

uniform vec4 uLightPosition6;
uniform float uLightAmbient6;
uniform float uLightDiffuse6;
uniform float uLightSpecular6;
uniform float uLightConstant6;
uniform float uLightLinear6;
uniform float uLightQuadratic6;
uniform float uAttenuation6;

uniform vec4 uLightPosition7;
uniform float uLightAmbient7;
uniform float uLightDiffuse7;
uniform float uLightSpecular7;
uniform float uLightConstant7;
uniform float uLightLinear7;
uniform float uLightQuadratic7;
uniform float uAttenuation7;

varying vec3 vPosition;
varying vec3 vNormal;
varying vec3 vBinormal;
varying vec3 vTangent;
varying vec2 vTexCoord;
varying vec2 vReflCoord;

mat3 cotangent_frame( vec3 N, vec3 p, vec2 uv ) {
    vec3 dp1 = dFdx( p );
    vec3 dp2 = dFdy( p );
    vec2 duv1 = dFdx( uv );
    vec2 duv2 = dFdy( uv );

    vec3 dp2perp = cross( dp2, N );
    vec3 dp1perp = cross( N, dp1 );
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    //    float invmax = 1.0 / sqrt( max( dot(T,T), dot(B,B) ) ); // opengles 2.0 doesn't support inversesqrt
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

vec3 computePointLight(vec3 normal, vec3 pos, vec3 lPos,
                        float lAmb, float lDif, float lSpec, float lConst, float lLin, float lQuad, float lAtt, 
                        vec3 mDif, vec3 mSpec, float mShin) {
    
    vec3 bivector = lPos - pos;

    float specularity = 1.0;
    
    #ifdef WITH_MATERIAL_SHININESS
        specularity = mShin;
    #endif

    float attenuation = 1.0;

    #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
        float distance = length(bivector);
        attenuation = 1.0 / (lConst + lLin * distance + lQuad * (distance * distance));
    #endif
    #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
        attenuation = lAtt;
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

    vec3 diffuse = vec3(0.0, 0.0, 0.0);
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

    //#ifdef WITH_FALLOF_SAMPLER
    //    vec2 longitudeLatitude = vec2((atan(normal.y, normal.x) / 3.1415926 + 1.0) * 0.5, (asin(normal.z) / 3.1415926 + 0.5));
    //    vec3 fallof = texture2D(uMaterialFallof, longitudeLatitude).xyz;    
    //    diffuse += fallof;
    //#endif

    vec3 specular = vec3(0.0, 0.0, 0.0);
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

    diffuse *= attenuation;
    specular *= attenuation;

    diffuse = clamp(diffuse, 0.0, 1.0);
    specular = clamp(specular, 0.0, 1.0);

    return (diffuse + specular);
}

vec4 computeTexel() {
    vec4 texel = vec4(0.0, 0.0, 0.0, 0.0);

    vec4 ambient = vec4(0.0, 0.0, 0.0, 0.0);
    #ifdef WITH_MATERIAL_AMBIENT
        ambient += uMaterialAmbient;
    #endif
    #ifdef WITH_AMBIENT_SAMPLER
        ambient += texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * vTexCoord);
    #endif

    texel += ambient;

    #ifdef WITH_V_POSITION
        #ifdef WITH_V_NORMAL
            vec3 normal = normalize(vNormal);

            #ifdef WITH_NORMAL_SAMPLER
                #ifdef WITH_TBN_FROM_NORMALS
                    normal = perturb_normal(normal, vPosition,  uNormalUnitCoords.xy + (uNormalUnitCoords.zw - uNormalUnitCoords.xy) * vTexCoord);
                #endif
            #endif
        #else
            #ifdef WITH_NORMAL_SAMPLER
                vec2 normalTexcoord = vec2(uNormalUnitCoords.xy + (uNormalUnitCoords.zw - uNormalUnitCoords.xy) * vTexCoord);
                vec3 normal = vec4(texture2D(normalMapUnit, normalTexcoord)).xyz * 255.0/127.0 - 128.0/127.0;

                #ifdef WITH_TBN_FROM_NORMALS
                    normal = perturb_normal(normal, vPosition,  normalTexcoord);
                #endif
            #endif
        #endif
        #ifdef WITH_LIGHT_POSITION
            #ifdef WITH_LIGHT_0
            texel += vec4(computePointLight(normal, vPosition.xyz, uLightPosition0.xyz, 
                                            uLightAmbient0, uLightDiffuse0, uLightSpecular0, uLightConstant0, uLightLinear0, uLightQuadratic0, uAttenuation0, 
                                            uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), ambient.w);
            #endif
            #ifdef WITH_LIGHT_1
            texel += vec4(computePointLight(normal, vPosition.xyz, uLightPosition1.xyz, 
                                            uLightAmbient1, uLightDiffuse1, uLightSpecular1, uLightConstant1, uLightLinear1, uLightQuadratic1, uAttenuation1, 
                                            uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), ambient.w);
            #endif
            #ifdef WITH_LIGHT_2
            texel += vec4(computePointLight(normal, vPosition.xyz, uLightPosition2.xyz, 
                                            uLightAmbient2, uLightDiffuse2, uLightSpecular2, uLightConstant2, uLightLinear2, uLightQuadratic2, uAttenuation2, 
                                            uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), ambient.w);
            #endif
            #ifdef WITH_LIGHT_3
            texel += vec4(computePointLight(normal, vPosition.xyz, uLightPosition3.xyz, 
                                            uLightAmbient3, uLightDiffuse3, uLightSpecular3, uLightConstant3, uLightLinear3, uLightQuadratic3, uAttenuation3, 
                                            uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), ambient.w);
            #endif
            #ifdef WITH_LIGHT_4
            texel += vec4(computePointLight(normal, vPosition.xyz, uLightPosition4.xyz, 
                                            uLightAmbient4, uLightDiffuse4, uLightSpecular4, uLightConstant4, uLightLinear4, uLightQuadratic4, uAttenuation4, 
                                            uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), ambient.w);
            #endif
            #ifdef WITH_LIGHT_5
            texel += vec4(computePointLight(normal, vPosition.xyz, uLightPosition5.xyz, 
                                            uLightAmbient5, uLightDiffuse5, uLightSpecular5, uLightConstant5, uLightLinear5, uLightQuadratic5, uAttenuation5, 
                                            uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), ambient.w);
            #endif
            #ifdef WITH_LIGHT_6
            texel += vec4(computePointLight(normal, vPosition.xyz, uLightPosition6.xyz, 
                                            uLightAmbient6, uLightDiffuse6, uLightSpecular6, uLightConstant6, uLightLinear6, uLightQuadratic6, uAttenuation6, 
                                            uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), ambient.w);
            #endif
            #ifdef WITH_LIGHT_7
            texel += vec4(computePointLight(normal, vPosition.xyz, uLightPosition7.xyz, 
                                            uLightAmbient7, uLightDiffuse7, uLightSpecular7, uLightConstant7, uLightLinear7, uLightQuadratic7, uAttenuation7, 
                                            uMaterialDiffuse.xyz, uMaterialSpecular.xyz, uMaterialShininess), ambient.w);
            #endif
        #endif
    #endif

    return texel;
}

void main() {
    gl_FragColor = computeTexel();

    #ifdef WITH_REFLECTION_SAMPLER
        gl_FragColor = mix(gl_FragColor, texture2D(reflectMapUnit, uReflectUnitCoords.xy + (uReflectUnitCoords.zw - uReflectUnitCoords.xy) * vReflCoord) , 0.35);
    #endif
}
"""
