//-----------------------------------------------------------
//Location of this shader, within the browser in material GUI
Shader "Custom/OceanWater"
{
    //--------------------
    //Tweakable properties
    Properties
    {
        //---------------------
        [Header(Main Settings)]
        [Toggle(FFT)] _FFT("Use FFT?", Float) = 0
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _ColorSSS("SSS Color", Color) = (1, 1, 1, 1)
        _SSS_Mult("SSS Mult", Float) = 1.0

        //-------------------
        [Header(Normal Maps)]
        [Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Strength", Float) = 1.0
        _BumpMovSpeed("Normal Mov Speed", Float) = 1.0

        [Normal] _BumpMapAlt("Normal Map Alt", 2D) = "bump" {}
        _BumpScaleAlt("Normal Strength Alt", Float) = 1.0
        _BumpMovSpeedAlt("Normal Mov Speed Alt", Float) = 1.0

        _BumpMovementDir("Normal Mov Dir", Float) = (0, 0, 0, 0)

        //----------------
        [Header(Specular)]
        _SpecGlossiness("Specular Glossiness", Float) = 32.0
        _SpecFresnelMult("Specular Fresnel Mult", Float) = 1.0
        _SpecStrength("Specular Strength", Float) = 1.0

        //------------------
        [Header(Reflection)]
        _ReflectionRoughness("Reflection Roughness", Range(0.0, 1.0)) = 0.25
        _ReflectionMult("Reflection Multiplier", Float) = 1.0
        _ReflectionStrength("Reflection Strength", Float) = 1.0

        //--------------------
        [Header(Tessellation)]
        _TessellationMult("Tessellation Multiplier", Range(1.0, 64.0)) = 1.0
        _TessellationMultShadow("Tessellation Multiplier Shadows", Range(0.0, 1.0)) = 1.0
        _TessellationMinDist("Tessellation Min Distance", Float) = 10.0
        _TessellationMaxDist("Tessellation Max Distance", Float) = 20.0

        //--------------------
        [Header(FFT)]
        _FFT_NormalStrength("FFT Normal Strength", Float) = 1.0
        /*_FFT_DisplacementStrength_Y("FFT Displacement Strength Y", Float) = 1.0
        _FFT_DisplacementStrength_XZ("FFT Displacement Strength XZ", Float) = 1.0
        _FFT_Scale("FFT Scale", Float) = 1.0*/
    }

    //-----------------------
    //The core of this shader
    SubShader
    {
        //https://docs.unity3d.com/2019.4/Documentation/Manual/SL-SubShaderTags.html
        Tags{ "Queue" = "Geometry" "RenderType" = "Opaque" "RenderPipeline" = "UniversalRenderPipeline" "IgnoreProjector" = "True"}

        //https://docs.unity3d.com/2019.4/Documentation/Manual/SL-ShaderLOD.html
        LOD 600

        //---------
        //Main pass
        Pass
        {
            //UniversalForward is a new LightMode tag useable in URP
            Name "ForwardPass" //https://docs.unity3d.com/Manual/SL-Name.html
            Tags { "LightMode" = "UniversalForward" } //https://docs.unity3d.com/Manual/SL-PassTags.html

            //Render state setup https://docs.unity3d.com/Manual/SL-Pass.html
            Cull Back
            ZTest LEqual
            ZWrite On
            Blend Off

            //--------------------------
            //The HLSL block of our pass
            HLSLPROGRAM

            // Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0
            #pragma require tessellation tessHW

            //------------
            //URP keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            //--------------
            //Unity keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog

            // -------------------------------------
            // Custom keywords
            #pragma shader_feature FFT

            //----------------------
            //Shader programs to run
            #pragma vertex ForwardPassVertex
            #pragma hull ForwardPassHull
            #pragma domain ForwardPassDomain
            #pragma fragment ForwardPassFragment

            //Required include for URP shaders, contains all built-in shader variables
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GeometricTools.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Tessellation.hlsl"

#ifndef FFT
            #include "Gerstner/Gerstner.hlsl"
#endif

            //-------------------
            //Vertex shader input
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                //float2 uv           : TEXCOORD0;
                float2 uvLM         : TEXCOORD1;
            };

            //-------------------
            //Hull shader input
            struct Attributes_Hull
            {
                //float2 uv                       : TEXCOORD0;
                float2 uvLM                     : TEXCOORD1;
                float4 positionWS_FogFactor     : TEXCOORD2;
                half3 normalWS                  : TEXCOORD3;
            };

            //---------------------
            //Patch constant output
            struct TessFactors
            {
                float edges[3]      : SV_TessFactor;
                float inside        : SV_InsideTessFactor;
            };

            //--------------------
            //Fragment shader input
            struct Varyings
            {
                float4 positionCS               : SV_POSITION;
                //float2 uv                       : TEXCOORD0;
                float2 uvLM                     : TEXCOORD1;
                float4 positionWS_FogFactor     : TEXCOORD2; // xyz: positionWS, w: vertex fog factor
                half3  normalWS                 : TEXCOORD3;
                half3  tangentWS                : TEXCOORD4;
                half3  binormalWS               : TEXCOORD5;
            };

            //--------------
            //Texture macros
            TEXTURE2D(_BumpMap); //Bump 
            SAMPLER(sampler_BumpMap);

            TEXTURE2D(_BumpMapAlt); //Bump alt
            SAMPLER(sampler_BumpMapAlt);

#ifdef FFT
            TEXTURE2D(_DisplacementFFT); //FFT result
            SAMPLER(sampler_DisplacementFFT);

            TEXTURE2D(_NormalFFT); //FFT surface normal
            SAMPLER(sampler_NormalFFT);
#endif

            //-------------------------
            //Parameters for our shader
            CBUFFER_START(UnityPerMaterial)
                //Main settings
                float4 _BaseColor;
                float4 _ColorSSS;
                float _SSS_Mult;

                //Normal maps
                float4 _BumpMap_ST;
                float _BumpScale;
                float _BumpMovSpeed;

                float4 _BumpMapAlt_ST;
                float _BumpScaleAlt;
                float _BumpMovSpeedAlt;

                float4 _BumpMovementDir;

                //Specular
                float _SpecGlossiness;
                float _SpecFresnelMult;
                float _SpecStrength;

                //Reflection
                float _ReflectionRoughness;
                float _ReflectionMult;
                float _ReflectionStrength;

                //Tessellation
                float _TessellationMult;
                float _TessellationMinDist;
                float _TessellationMaxDist;

                //Gerstner
#ifndef FFT
                StructuredBuffer<GerstnerWave> _GerstnerWavesLowFreq;
                int _GerstnerWavesLowFreqCount;
                StructuredBuffer<GerstnerWave> _GerstnerWavesHighFreq;
                int _GerstnerWavesHighFreqCount;
#else
                //FFT
                float4 _DisplacementFFT_ST;
                //float4 _DisplacementFFT_TexelSize;
                float4 _NormalFFT_ST;
                float _FFT_DisplacementStrength_Y;
                float _FFT_DisplacementStrength_XZ;
                float _FFT_Scale;
                float _FFT_Res;
                float _FFT_NormalStrength;
#endif
            CBUFFER_END

            //-------------
            //Vertex shader
            Attributes_Hull ForwardPassVertex(Attributes input)
            {
                //Zero initialise
                Attributes_Hull output = (Attributes_Hull)0;

                //------------------------------------------------------------------------------------------------------------------------
                //VertexPositionInputs is a helper struct with our vertex in multiple spaces
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                //VertexNormalInputs contains the normal/tangent/bitangent in world space
                VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                //UV stuff
                //output.uv = input.uv;
                output.uvLM = input.uvLM.xy * unity_LightmapST.xy + unity_LightmapST.zw;

                //Normal
                output.normalWS = vertexNormalInput.normalWS;

                //Per-vertex fog factor + world-space pos
                const float fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                output.positionWS_FogFactor = float4(vertexInput.positionWS, fogFactor);
                //------------------------------------------------------------------------------------------------------------------------

                //Finished
                return output;
            }

            //Helper for fragment shader
            half3 DoLighting(Light light, half3 normalWS, half3 viewDirectionWS)
            {
                //Initialise
                half3 color = 0.0f;
                const float fresnelTerm = 1.0f - dot(viewDirectionWS, normalWS);
                
                //Attenuation
                const float totalAttenuation = light.shadowAttenuation * light.distanceAttenuation;

                //Difuse
                const float NdotL = dot(light.direction, normalWS) * totalAttenuation;
                color += max(0.0f, _BaseColor.xyz * NdotL * light.color);

                //Specular
                const half3 halfVector = normalize(viewDirectionWS + light.direction);
                const float HdotN = max(0.0f, dot(halfVector, normalWS));
                color += max(0.0f, totalAttenuation * light.color * pow(abs(HdotN), _SpecGlossiness / max(0.0001f, fresnelTerm * _SpecFresnelMult)) * _SpecStrength);

                //Fake SSS
                const float strengthSSS = max(0.0f, dot(normalWS, -light.direction) * fresnelTerm * saturate(dot(viewDirectionWS, -light.direction)));
                color += max(0.0f, _ColorSSS.xyz * light.color * light.distanceAttenuation * pow(strengthSSS, abs(_SSS_Mult)));

                //Finished
                return color;
            }

            //---------------
            //Fragment shader
            half4 ForwardPassFragment(Varyings input) : SV_Target
            {
                //----------
                //Initialise
                half3 color = 0.0f;
                const float2 uv = input.positionWS_FogFactor.xz;

                //------------------------------------------------------------------------------------------------------------------------
                //Normal maps (two moving maps)
                half3 normalWS = input.normalWS;
                {
#ifdef FFT
                    //Compute normal FFT
                    const float2 newUV = float2(uv / float2(_FFT_Res, _FFT_Res)) * _FFT_Scale;
                    const float mult = _FFT_DisplacementStrength_Y * _FFT_NormalStrength;
                    const float3 offset = float3(1.0f / _FFT_Res, 1.0f / _FFT_Res, 0.0f);

                    const float3 left = float3(-1.0f, SAMPLE_TEXTURE2D(_DisplacementFFT, sampler_DisplacementFFT, newUV - offset.xz).y * mult, 0.0f);
                    const float3 right = float3(1.0f, SAMPLE_TEXTURE2D(_DisplacementFFT, sampler_DisplacementFFT, newUV + offset.xz).y * mult, 0.0f);
                    const float3 top = float3(0.0f, SAMPLE_TEXTURE2D(_DisplacementFFT, sampler_DisplacementFFT, newUV - offset.zy).y * mult, -1.0f);
                    const float3 bottom = float3(0.0f, SAMPLE_TEXTURE2D(_DisplacementFFT, sampler_DisplacementFFT, newUV + offset.zy).y * mult, 1.0f);

                    const float3 tangentWS = normalize(float3((bottom - top)));
                    const float3 binormalWS = normalize(float3((right - left)));
                    normalWS = normalize(cross(tangentWS, binormalWS));
#else
                    const float3 tangentWS = input.tangentWS;
                    const float3 binormalWS = input.binormalWS;
#endif

                    //Main normal map
                    {
                        const float2 newUV = TRANSFORM_TEX(uv + _Time.y * _BumpMovSpeed * normalize(_BumpMovementDir.xy), _BumpMap);

                        const half3 unpackedNormal = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, newUV), _BumpScale);

                        normalWS = TransformTangentToWorld(unpackedNormal,
                            half3x3(tangentWS, binormalWS, normalWS));
                    }

                    //Secondary normal map
                    {
                        const float2 newUV = TRANSFORM_TEX(uv + _Time.y * _BumpMovSpeedAlt * normalize(_BumpMovementDir.zw), _BumpMapAlt);

                        const half3 unpackedNormal = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMapAlt, sampler_BumpMapAlt, newUV), _BumpScaleAlt);

                        normalWS += TransformTangentToWorld(unpackedNormal,
                            half3x3(tangentWS, binormalWS, normalWS));
                    }

                    //Normalise result of the two
                    normalWS = normalize(normalWS);
                }

                //---------------------------------
                //Used in view dependent components
                const half3 positionWS = input.positionWS_FogFactor.xyz;
                const half3 viewDirectionWS = SafeNormalize(GetCameraPositionWS() - positionWS);

                //---------
                //Lightmaps
                {
                #ifdef LIGHTMAP_ON
                    //Normal is required in case Directional lightmaps are baked
                    half3 bakedGI = SampleLightmap(input.uvLM, normalWS);
                #else
                    //Samples SH fully per-pixel
                    half3 bakedGI = SampleSH(normalWS);
                #endif

                    color += bakedGI * _BaseColor.xyz;
                }

                //-----------------
                //Directional light
                {
                #ifdef _MAIN_LIGHT_SHADOWS
                    Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS_FogFactor.xyz));
                #else
                    Light mainLight = GetMainLight();
                #endif

                    //Add light
                    color += DoLighting(mainLight, normalWS, viewDirectionWS);
                }

                //------------
                //Other lights
                {
                #ifdef _ADDITIONAL_LIGHTS
                    const int additionalLightsCount = GetAdditionalLightsCount();
                    for (int i = 0; i < additionalLightsCount; ++i)
                    {
                        //Obtain additional lights
                        Light light = GetAdditionalLight(i, positionWS);

                        //Add light
                        color += DoLighting(light, normalWS, viewDirectionWS);
                    }
                #endif
                }

                //-----------
                //Reflections
                {
                    const float fresnelTerm = (1.0f - dot(viewDirectionWS, normalWS) / _ReflectionMult);
                    const float finalReflectionStrength = fresnelTerm * _ReflectionStrength;

                    const float3 reflection = GlossyEnvironmentReflection(reflect(-viewDirectionWS, normalWS), _ReflectionRoughness, finalReflectionStrength);
                    color.xyz = lerp(color.xyz, reflection, saturate(finalReflectionStrength));
                }

                //---
                //Fog
                {
                    //Mix final colour with fog colour, according to fog factor
                    const float fogFactor = input.positionWS_FogFactor.w;
                    color = MixFog(color, fogFactor);
                }
                //------------------------------------------------------------------------------------------------------------------------

                //--------
                //Finished
                return half4(color, 1.0f);
            }
            
            //--------------------------------------------------------------------------------------------------------
            //Hull shader
            //https://docs.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-hull-shader-design
            [domain("tri")]
            [partitioning("fractional_odd")]
            [outputtopology("triangle_cw")]
            [outputcontrolpoints(3)]
            [patchconstantfunc("ForwardPassHull_Patch")]
            Attributes_Hull ForwardPassHull(
                InputPatch<Attributes_Hull, 3> input,
                uint i : SV_OutputControlPointID)
            {
                //We don't need to modify the data in any way
                return input[i];
            }

            //Patch function for hull shader
            TessFactors ForwardPassHull_Patch(InputPatch<Attributes_Hull, 3> input)
            {
                //Zero initialise
                TessFactors output = (TessFactors)0;

                //Obtain distance based tess factors
                const float3 distanceFactors = GetDistanceBasedTessFactor(
                    input[0].positionWS_FogFactor.xyz,
                    input[1].positionWS_FogFactor.xyz,
                    input[2].positionWS_FogFactor.xyz,
                    GetCameraPositionWS(), _TessellationMinDist, _TessellationMaxDist);

                //Modify factors to static multiplier
                //Max to 1.0f otherwise we lose geometry
                output.edges[0] = max(1.0f, _TessellationMult * distanceFactors.x);
                output.edges[1] = max(1.0f, _TessellationMult * distanceFactors.y);
                output.edges[2] = max(1.0f, _TessellationMult * distanceFactors.z);
                output.inside = (output.edges[0] + output.edges[1] + output.edges[2]) / 3.0f;

                //Finished
                return output;
            }

            //----------------------------------------------------------------------------------------------------------
            //Domain shader
            //https://docs.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-domain-shader-design
            [domain("tri")]
            Varyings ForwardPassDomain(
                TessFactors factors,
                float3 uvw : SV_DomainLocation,
                const OutputPatch<Attributes_Hull, 3> patch)
            {
                //---------------
                //First, construct a new input based on barycentric coordinates and given patch
                Attributes_Hull input = (Attributes_Hull)0;
                input.positionWS_FogFactor = patch[0].positionWS_FogFactor * uvw.x + patch[1].positionWS_FogFactor * uvw.y + patch[2].positionWS_FogFactor * uvw.z;
                input.normalWS = patch[0].normalWS * uvw.x + patch[1].normalWS * uvw.y + patch[2].normalWS * uvw.z;
                //input.uv = patch[0].uv * uvw.x + patch[1].uv * uvw.y + patch[2].uv * uvw.z;
                input.uvLM = patch[0].uvLM * uvw.x + patch[1].uvLM * uvw.y + patch[2].uvLM * uvw.z;
                
                //Zero initialise
                Varyings output = (Varyings)0;

                //Transfer data
                output.positionWS_FogFactor = input.positionWS_FogFactor;
                output.normalWS = input.normalWS;
                //output.uv = input.uv;
                output.uvLM = input.uvLM;

#ifndef FFT
                //Use gerstner on worldpos
                DoGerstner(output.positionWS_FogFactor.xyz, _Time.y, output.normalWS, output.binormalWS, output.tangentWS,
                    _GerstnerWavesLowFreq, _GerstnerWavesLowFreqCount, _GerstnerWavesHighFreq, _GerstnerWavesHighFreqCount);
#else
                //Compute displacement off the FFT result
                const float2 uv = float2(output.positionWS_FogFactor.xz / float2(_FFT_Res, _FFT_Res)) * _FFT_Scale;
                const float3 sampledDisp = _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv, 0.0f).xyz;
                const float3 displacement = float3(sampledDisp.x * _FFT_DisplacementStrength_XZ, sampledDisp.y * _FFT_DisplacementStrength_Y, sampledDisp.z * _FFT_DisplacementStrength_XZ);
                output.positionWS_FogFactor.xyz += displacement;

                output.tangentWS = float3(1.0f, 0.0f, 0.0f);
                output.normalWS = float3(0.0f, 1.0f, 0.0f);
                output.binormalWS = float3(0.0f, 0.0f, 1.0f);
#endif

                //Transform world space -> clip space (using view projection matrix)
                //https://docs.unity3d.com/Manual/SL-UnityShaderVariables.html
                output.positionCS = mul(UNITY_MATRIX_VP, float4(output.positionWS_FogFactor.xyz, 1.0f));

                //--------
                //Finished
                return output;
            }

            ENDHLSL
        }

        //-----------
        //Shadow pass
        Pass
        {
            //ShadowCaster is a LightMode tag associated to the shadow pass
            Name "ShadowCaster" //https://docs.unity3d.com/Manual/SL-Name.html
            Tags { "LightMode" = "ShadowCaster" } //https://docs.unity3d.com/Manual/SL-PassTags.html

            //Render state setup https://docs.unity3d.com/Manual/SL-Pass.html
            ColorMask 0 //Write to depth only
            Cull Off
            ZTest LEqual
            ZWrite On
            Blend Off

            //--------------------------
            //The HLSL block of our pass
            HLSLPROGRAM

            // Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0
            #pragma require tessellation tessHW

            // -------------------------------------
            // Custom keywords
            #pragma shader_feature FFT

            //----------------------
            //Shader programs to run
            #pragma vertex ShadowPassVertex
            #pragma hull ShadowPassHull
            #pragma domain ShadowPassDomain
            #pragma fragment ShadowPassFragment

            //Required include for URP shaders, contains all built-in shader variables
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GeometricTools.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Tessellation.hlsl"

#ifndef FFT
            #include "Gerstner/Gerstner.hlsl"
#endif

            //-------------------
            //Vertex shader input
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
            };

            //-------------------
            //Hull shader input
            struct Attributes_Hull
            {
                float4 positionWS_FogFactor     : TEXCOORD2;
                half3 normalWS                  : TEXCOORD3;
            };

            //---------------------
            //Patch constant output
            struct TessFactors
            {
                float edges[3]      : SV_TessFactor;
                float inside        : SV_InsideTessFactor;
            };

            //--------------------
            //Fragment shader input
            struct Varyings
            {
                float4 positionCS               : SV_POSITION;
                float4 positionWS_FogFactor     : TEXCOORD2; // xyz: positionWS, w: vertex fog factor
            };
            
            //--------------
            //Texture macros
#ifdef FFT
            TEXTURE2D(_DisplacementFFT); //FFT result
            SAMPLER(sampler_DisplacementFFT);
#endif

            float3 _LightDirection;

            //-------------------------
            //Parameters for our shader
            CBUFFER_START(UnityPerMaterial)
                float _TessellationMult;
                float _TessellationMultShadow;

                float _TessellationMinDist;
                float _TessellationMaxDist;

#ifndef FFT
                StructuredBuffer<GerstnerWave> _GerstnerWavesLowFreq;
                int _GerstnerWavesLowFreqCount;
                StructuredBuffer<GerstnerWave> _GerstnerWavesHighFreq;
                int _GerstnerWavesHighFreqCount;
#else
                float4 _DisplacementFFT_ST;
                float4 _DisplacementFFT_TexelSize;
                float _FFT_DisplacementStrength_Y;
                float _FFT_DisplacementStrength_XZ;
                float _FFT_Scale;
                float _FFT_Res;
                float _FFT_NormalStrength;
#endif
            CBUFFER_END

            //-------------
            //Vertex shader
            Attributes_Hull ShadowPassVertex(Attributes input)
            {
                //Zero initialise
                Attributes_Hull output = (Attributes_Hull)0;

                //------------------------------------------------------------------------------------------------------------------------
                //VertexPositionInputs is a helper struct with our vertex in multiple spaces
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

                //VertexNormalInputs contains the normal/tangent/bitangent in world space
                VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                //Normal
                output.normalWS = vertexNormalInput.normalWS;

                //Per-vertex fog factor + world-space pos
                const float fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                output.positionWS_FogFactor = float4(vertexInput.positionWS, fogFactor);
                //------------------------------------------------------------------------------------------------------------------------

                //Finished
                return output;
            }

            //---------------
            //Fragment shader
            half4 ShadowPassFragment(Varyings input) : SV_Target
            {
                return 0.0f;
            }
            
            //--------------------------------------------------------------------------------------------------------
            //Hull shader
            //https://docs.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-hull-shader-design
            [domain("tri")]
            [partitioning("fractional_odd")]
            [outputtopology("triangle_cw")]
            [outputcontrolpoints(3)]
            [patchconstantfunc("ShadowPassHull_Patch")]
            Attributes_Hull ShadowPassHull(
                InputPatch<Attributes_Hull, 3> input,
                uint i : SV_OutputControlPointID)
            {
                //We don't need to modify the data in any way
                return input[i];
            }

            //Patch function for hull shader
            TessFactors ShadowPassHull_Patch(InputPatch<Attributes_Hull, 3> input)
            {
                //Zero initialise
                TessFactors output = (TessFactors)0;

                //Obtain distance based tess factors
                const float3 distanceFactors = GetDistanceBasedTessFactor(
                    input[0].positionWS_FogFactor.xyz,
                    input[1].positionWS_FogFactor.xyz,
                    input[2].positionWS_FogFactor.xyz,
                    GetCameraPositionWS(), _TessellationMinDist, _TessellationMaxDist);

                //Modify factors to static multiplier
                //Max to 1.0f otherwise we lose geometry
                output.edges[0] = max(1.0f, _TessellationMult * _TessellationMultShadow * distanceFactors.x);
                output.edges[1] = max(1.0f, _TessellationMult * _TessellationMultShadow * distanceFactors.y);
                output.edges[2] = max(1.0f, _TessellationMult * _TessellationMultShadow * distanceFactors.z);
                output.inside = (output.edges[0] + output.edges[1] + output.edges[2]) / 3.0f;

                //Finished
                return output;
            }

            //----------------------------------------------------------------------------------------------------------
            //Domain shader
            //https://docs.microsoft.com/en-us/windows/win32/direct3d11/direct3d-11-advanced-stages-domain-shader-design
            [domain("tri")]
            Varyings ShadowPassDomain(
                TessFactors factors,
                float3 uvw : SV_DomainLocation,
                const OutputPatch<Attributes_Hull, 3> patch)
            {
                //---------------
                //First, construct a new input based on barycentric coordinates and given patch
                Attributes_Hull input = (Attributes_Hull)0;
                input.positionWS_FogFactor = patch[0].positionWS_FogFactor * uvw.x + patch[1].positionWS_FogFactor * uvw.y + patch[2].positionWS_FogFactor * uvw.z;
                
                //Zero initialise
                Varyings output = (Varyings)0;

                //Transfer data
                output.positionWS_FogFactor = input.positionWS_FogFactor;

#ifndef FFT
                //Use gerstner on worldpos
                float3 normalWS = float3(0.0f, 0.0f, 0.0f);
                float3 binormalWS = float3(0.0f, 0.0f, 0.0f);
                float3 tangentWS = float3(0.0f, 0.0f, 0.0f);
                DoGerstner(output.positionWS_FogFactor.xyz, _Time.y, normalWS, binormalWS, tangentWS,
                    _GerstnerWavesLowFreq, _GerstnerWavesLowFreqCount, _GerstnerWavesHighFreq, _GerstnerWavesHighFreqCount);
#else
                float3 normalWS = float3(0.0f, 1.0f, 0.0f);

                const float2 uv = float2((output.positionWS_FogFactor.xz / float2(_FFT_Res, _FFT_Res)) * _FFT_Scale);
                const float3 sampledDisp = _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv, 0.0f).xyz;
                const float3 displacement = float3(sampledDisp.x * _FFT_DisplacementStrength_XZ, sampledDisp.y * _FFT_DisplacementStrength_Y, sampledDisp.z * _FFT_DisplacementStrength_XZ);
                output.positionWS_FogFactor.xyz += displacement;

                //Compute normal FFT, required by shadow bias
                {
                    const float mult = _FFT_DisplacementStrength_Y * _FFT_NormalStrength;
                    const float3 offset = float3(1.0f / _FFT_Res, 1.0f / _FFT_Res, 0.0f);

                    const float3 left = float3(-1.0f, _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv - offset.xz, 0.0f).y * mult, 0.0f);
                    const float3 right = float3(1.0f, _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv + offset.xz, 0.0f).y * mult, 0.0f);
                    const float3 top = float3(0.0f, _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv - offset.zy, 0.0f).y * mult, -1.0f);
                    const float3 bottom = float3(0.0f, _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv + offset.zy, 0.0f).y * mult, 1.0f);

                    const float3 tangentWS = normalize(float3((bottom - top)));
                    const float3 binormalWS = normalize(float3((right - left)));
                    normalWS = normalize(cross(tangentWS, binormalWS));
                }
#endif

                //Transform world space -> clip space (using view projection matrix)
                //https://docs.unity3d.com/Manual/SL-UnityShaderVariables.html
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(output.positionWS_FogFactor.xyz, normalWS, _LightDirection));

                //Fix shadow artifacts
                {
                    //Depending on Unity depth buffer settings, use either min or max
                    #if UNITY_REVERSED_Z
                    output.positionCS.z = min(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                    #else
                    output.positionCS.z = max(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                    #endif
                }

                //--------
                //Finished
                return output;
            }

            ENDHLSL
        }

        // Used for depth prepass
        // If shadows cascade are enabled we need to perform a depth prepass. 
        // We also need to use a depth prepass in some cases camera require depth texture
        // (e.g, MSAA is enabled and we can't resolve with Texture2DMS
        UsePass "Universal Render Pipeline/Lit/DepthOnly"

        // Used for Baking GI. This pass is stripped from build.
        UsePass "Universal Render Pipeline/Lit/Meta"
    }
}
