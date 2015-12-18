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

uniform vec4 uMaterialAmbient;
uniform vec4 uMaterialDiffuse;
uniform vec4 uMaterialSpecular;
uniform float uMaterialShininess;

uniform vec4 uLightPosition;
uniform float uLightAmbient;
uniform float uLightDiffuse;
uniform float uLightSpecular;
uniform float uLightConstant;
uniform float uLightLinear;
uniform float uLightQuadratic;
uniform float uAttenuation;

varying vec3 vPosition;
varying vec3 vNormal;
varying vec3 vBinormal;
varying vec3 vTangent;
varying vec2 vTexCoord;

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
#ifdef WITH_LIGHT_POSITION
    #ifdef WITH_V_POSITION
        vec3 computePointLight(vec3 normal) {
            vec3 bivector = uLightPosition.xyz - vPosition.xyz;

            float specularity = 1.0;
            
            #ifdef WITH_MATERIAL_SHININESS
                specularity = uMaterialShininess;
            #endif

            float attenuation = 1.0;

            #ifdef WITH_LIGHT_DYNAMIC_ATTENUATION
                float distance = length(bivector);
                attenuation = 1.0 / (uLightConstant + uLightLinear * distance + uLightQuadratic * (distance * distance));
            #endif
            #ifdef WITH_LIGHT_PRECOMPUTED_ATTENUATION
                attenuation = uAttenuation;
            #endif
            #ifdef WITH_GLOSS_SAMPLER
                vec2  roughnessV = texture2D(glossMapUnit, uGlossUnitCoords.xy + (uGlossUnitCoords.zw - uGlossUnitCoords.xy) * vTexCoord).rg;
                float roughness = (1-roughnessV.r) + uMaterialDiffuse.z * (1.0 - roughnessV.g);
            #endif
            #ifdef WITH_SPECULAR_SAMPLER
                //vec2 specularityV = texture2D(specularMapUnit, uSpecularUnitCoords.xy + (uSpecularUnitCoords.zw - uSpecularUnitCoords.xy) * vTexCoord).rg;
                //float specularity = (1-specularityV.r) + uMaterialSpecular.z * (1.0 - specularityV.g);

                specularity = texture2D(specularMapUnit, uSpecularUnitCoords.xy + (uSpecularUnitCoords.zw - uSpecularUnitCoords.xy) * vTexCoord).r * 255.0;
            #endif

            vec3 L = normalize(bivector);
            vec3 E = normalize(-vPosition);
            vec3 R = normalize(-reflect(L, normal));

            vec3 diffuse = vec3(0.0, 0.0, 0.0);
                #ifdef WITH_MATERIAL_DIFFUSE
                   diffuse += uMaterialDiffuse.xyz;
                #endif
                #ifdef WITH_LIGHT_DIFFUSE
                    diffuse *= uLightDiffuse;
                #endif
                #ifdef WITH_GLOSS_SAMPLER
                    diffuse *= roughness;
                #endif
            diffuse *= max(dot(normal, L), 0.0);


            vec3 specular = vec3(0.0, 0.0, 0.0);
                #ifdef WITH_MATERIAL_SPECULAR
                    specular += uMaterialSpecular.xyz;
                #endif
                #ifdef WITH_LIGHT_SPECULAR
                    specular *= uLightSpecular;
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
    #endif
#endif

vec4 computeTexel() {
    vec4 texel = vec4(0.0, 0.0, 0.0, 0.0);

    vec4 ambient = vec4(0.0, 0.0, 0.0, 0.0);
    #ifdef WITH_MATERIAL_AMBIENT
        ambient += uMaterialAmbient;
    #endif
    #ifdef WITH_AMBIENT_SAMPLER
        ambient += texture2D(texUnit, uTexUnitCoords.xy + (uTexUnitCoords.zw - uTexUnitCoords.xy) * vTexCoord);
    #endif

    #ifdef WITH_LIGHT_AMBIENT
        ambient *= uLightAmbient;
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

            #ifdef WITH_LIGHT_POSITION
                texel += vec4(computePointLight(normal), 1.0);
            #endif
        #else
            #ifdef WITH_NORMAL_SAMPLER
                vec2 normalTexcoord = vec2(uNormalUnitCoords.xy + (uNormalUnitCoords.zw - uNormalUnitCoords.xy) * vTexCoord);
                vec3 normal = vec4(texture2D(normalMapUnit, normalTexcoord)).xyz * 255.0/127.0 - 128.0/127.0;

                #ifdef WITH_TBN_FROM_NORMALSs
                    normal = perturb_normal(normal, vPosition,  normalTexcoord);
                #endif
            #endif

            #ifdef WITH_LIGHT_POSITION
                texel += vec4(computePointLight(normal), 1.0);
            #endif
        #endif
    #endif

    return texel;
}

void main() {
    gl_FragColor = computeTexel();
}
"""
