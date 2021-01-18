//-----------------------------------------------------------
//Location of this shader, within the browser in material GUI
Shader "Custom/TessellationBase"
{
    //--------------------
    //Tweakable properties
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _TessellationMult("Tessellation Multiplier", Range(1.0, 64.0)) = 1.0
        _TessellationShape("Tessellation Shape", Range(0.0, 1.0)) = 0.0
        _TessellationMinDist("Tessellation Min Distance", Float) = 10.0
        _TessellationMaxDist("Tessellation Max Distance", Float) = 20.0
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

            //-------------------
            //Vertex shader input
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv           : TEXCOORD0;
                float2 uvLM         : TEXCOORD1;
            };

            //-------------------
            //Hull shader input
            struct Attributes_Hull
            {
                float2 uv                       : TEXCOORD0;
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
                float2 uv                       : TEXCOORD0;
                float2 uvLM                     : TEXCOORD1;
                float4 positionWS_FogFactor     : TEXCOORD2; // xyz: positionWS, w: vertex fog factor
                half3  normalWS                 : TEXCOORD3;
            };

            //-------------------------
            //Parameters for our shader
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;

                float _TessellationMult;
                float _TessellationShape;

                float _TessellationMinDist;
                float _TessellationMaxDist;
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
                output.uv = input.uv;
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
                
                //Difuse
                const float NdotL = dot(light.direction, normalWS) * light.shadowAttenuation * light.distanceAttenuation;
                color += max(0.0f, _BaseColor.xyz * NdotL * light.color);

                //Specular test
                half3 halfVector = normalize(viewDirectionWS + light.direction);
                float HdotN = max(0.0f, dot(halfVector, normalWS));
                color += light.shadowAttenuation * light.distanceAttenuation * light.color * pow(abs(HdotN), 32.0f) * 5.0f;

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

                //------------------------------------------------------------------------------------------------------------------------
                //Normal
                const half3 normalWS = normalize(input.normalWS);

                //Used in view dependent components
                const half3 positionWS = input.positionWS_FogFactor.xyz;
                const half3 viewDirectionWS = SafeNormalize(GetCameraPositionWS() - positionWS);

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
                input.uv = patch[0].uv * uvw.x + patch[1].uv * uvw.y + patch[2].uv * uvw.z;
                input.uvLM = patch[0].uvLM * uvw.x + patch[1].uvLM * uvw.y + patch[2].uvLM * uvw.z;
                
                //Zero initialise
                Varyings output = (Varyings)0;

                //Transfer data
                output.positionWS_FogFactor = input.positionWS_FogFactor;
                output.normalWS = input.normalWS;
                output.uv = input.uv;
                output.uvLM = input.uvLM;

                //Modify worldpos according to PhongTessellation
                //Moves vertices along normal
                output.positionWS_FogFactor.xyz = PhongTessellation(
                    input.positionWS_FogFactor.xyz,
                    patch[0].positionWS_FogFactor.xyz, patch[1].positionWS_FogFactor.xyz, patch[2].positionWS_FogFactor.xyz,
                    patch[0].normalWS, patch[1].normalWS, patch[2].normalWS,
                    uvw, _TessellationShape);

                //Transform world space -> clip space (using view projection matrix)
                //https://docs.unity3d.com/Manual/SL-UnityShaderVariables.html
                output.positionCS = mul(UNITY_MATRIX_VP, float4(output.positionWS_FogFactor.xyz, 1.0f));

                //--------
                //Finished
                return output;
            }

            ENDHLSL
        }

        // Used for rendering shadowmaps
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"

        // Used for depth prepass
        // If shadows cascade are enabled we need to perform a depth prepass. 
        // We also need to use a depth prepass in some cases camera require depth texture
        // (e.g, MSAA is enabled and we can't resolve with Texture2DMS
        UsePass "Universal Render Pipeline/Lit/DepthOnly"

        // Used for Baking GI. This pass is stripped from build.
        UsePass "Universal Render Pipeline/Lit/Meta"
    }
}
