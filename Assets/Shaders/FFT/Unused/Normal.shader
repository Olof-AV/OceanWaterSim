//-----------------------------------------------------------
//Location of this shader, within the browser in material GUI
Shader "Custom/FFT_Normal"
{
    //--------------------
    //Tweakable properties
    Properties
    {
        //---------------------
        //Empty
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
            ZTest Always
            ZWrite Off
            Blend Off

            //--------------------------
            //The HLSL block of our pass
            HLSLPROGRAM

            // Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            //----------------------
            //Shader programs to run
            #pragma vertex ForwardPassVertex
            #pragma fragment ForwardPassFragment

            //Required include for URP shaders, contains all built-in shader variables
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            //-------------------
            //Vertex shader input
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
            };

            //--------------------
            //Fragment shader input
            struct Varyings
            {
                float4 positionCS               : SV_POSITION;
                float2 uv                       : TEXCOORD0;
            };

            //--------------
            //Texture macros
            TEXTURE2D(_DisplacementFFT);
            SAMPLER(sampler_DisplacementFFT);

            //-------------------------
            //Parameters for our shader
            CBUFFER_START(UnityPerMaterial)

                //FFT stuff
                float4 _DisplacementFFT_ST;
                float4 _DisplacementFFT_TexelSize;
                float _FFT_DisplacementStrength_Y;
            CBUFFER_END

            //-------------
            //Vertex shader
            Attributes ForwardPassVertex(Attributes input)
            {
                //Zero initialise
                Varyings output = (Varyings)0;

                //------------------------------------------------------------------------------------------------------------------------
                //VertexPositionInputs is a helper struct with our vertex in multiple spaces
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;

                //UV stuff
                output.uv = input.uv;
                //------------------------------------------------------------------------------------------------------------------------

                //Finished
                return output;
            }

            //---------------
            //Fragment shader
            half4 ForwardPassFragment(Varyings input) : SV_Target
            {
                const float2 uv = input.uv;
                const float3 mult = float3(1.0f, _FFT_DisplacementStrength_Y, 1.0f);
                const float3 offset = float3(_DisplacementFFT_TexelSize.xy, 0.0f);

                const float3 left = _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv - offset.xz, 0.0f).xyz * mult;
                const float3 right = _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv + offset.xz, 0.0f).xyz * mult;
                const float3 top = _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv - offset.yz, 0.0f).xyz * mult;
                const float3 bottom = _DisplacementFFT.SampleLevel(sampler_DisplacementFFT, uv + offset.yz, 0.0f).xyz * mult;

                const float3 normal = normalize(float3(top.y - bottom.y, left.y - right.y, 2.0f));

                return float4(normal.x + 0.5f, normal.y + 0.5f, normal.z, 1.0f);
            }

            ENDHLSL
        }
    }
}
