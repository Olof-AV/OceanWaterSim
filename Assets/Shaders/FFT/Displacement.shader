//-----------------------------------------------------------
//Location of this shader, within the browser in material GUI
Shader "Custom/FFT_Displacement"
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
            TEXTURE2D(_DisplacementFFT_X);
            SAMPLER(sampler_DisplacementFFT_X);

            TEXTURE2D(_DisplacementFFT_Y);
            SAMPLER(sampler_DisplacementFFT_Y);

            TEXTURE2D(_DisplacementFFT_Z);
            SAMPLER(sampler_DisplacementFFT_Z);

            //-------------------------
            //Parameters for our shader
            CBUFFER_START(UnityPerMaterial)

                //Textures
                float4 _DisplacementFFT_X_ST;
                float4 _DisplacementFFT_Y_ST;
                float4 _DisplacementFFT_Z_ST;
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
                const float r = SAMPLE_TEXTURE2D(_DisplacementFFT_X, sampler_DisplacementFFT_X, input.uv).r;
                const float g = SAMPLE_TEXTURE2D(_DisplacementFFT_Y, sampler_DisplacementFFT_Y, input.uv).r;
                const float b = SAMPLE_TEXTURE2D(_DisplacementFFT_Z, sampler_DisplacementFFT_Z, input.uv).r;

                return half4(r, g, b, 1.0f);
            }

            ENDHLSL
        }
    }
}
