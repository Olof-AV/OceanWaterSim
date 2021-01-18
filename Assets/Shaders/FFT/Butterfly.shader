//-----------------------------------------------------------
//Location of this shader, within the browser in material GUI
Shader "Custom/FFT_Butterfly"
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
            TEXTURE2D(_ButterflyTex); //Spectrum
            SAMPLER(sampler_ButterflyTex);

            //-------------------------
            //Parameters for our shader
            CBUFFER_START(UnityPerMaterial)

                //FFT parameters
                float4 _ButterflyTex_ST;
                //float4 _ButterflyTex_TexelSize;
                float _FFT_Size;
                float _FFT_Res;

                float4 _FFT_Wind;

                float _FFT_FourierAmpSpeedMult;

                StructuredBuffer<int> _BitReversedIndices;
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

            //---------------------------------------
            //Helper functions for complex operations

            //https://www.expii.com/t/exponential-form-of-a-complex-number-9210
            float2 compExp(const float a)
            {
                return float2(cos(a), sin(a));
            }

            //---------------
            //Fragment shader
            half4 ForwardPassFragment(Varyings input) : SV_Target
            {
                //----------
                //Initialise
                half4 col = 0.0f;
                const float N = _FFT_Res;
                const float2 coords = float2(int2(input.positionCS.x, input.positionCS.y));

                //const float exponentK = fmod((coords.y * N) / pow(2.0f, coords.x + 1.0f), N);
                const float exponentK = fmod(coords.y * (N / pow(2.0f, coords.x + 1.0f)), N);

                const float2 twiddle = compExp(TWO_PI * exponentK / N);
                const float butterflySpan = pow(2.0f, coords.x);
                const bool isTopWing = fmod(coords.y, pow(2.0f, coords.x + 1.0f)) < butterflySpan;

                //Store twiddle factors in XY
                col.xy = twiddle;

                //First stage uses array of numbers arranged in bit-reversed order
                if ((int)coords.x == 0)
                {
                    //Top wing
                    if (isTopWing)
                    {
                        col.z = _BitReversedIndices[coords.y];
                        col.w = _BitReversedIndices[coords.y + 1];
                    }
                    //Bottom wing
                    else
                    {
                        col.z = _BitReversedIndices[coords.y - 1];
                        col.w = _BitReversedIndices[coords.y];
                    }
                }
                //The other stages function off the current pixel coords and the butterfly span
                else
                {
                    //Top wing
                    if (isTopWing)
                    {
                        col.z = coords.y;
                        col.w = coords.y + butterflySpan;
                    }
                    //Bottom wing
                    else
                    {
                        col.z = coords.y - butterflySpan;
                        col.w = coords.y;
                    }
                }

                //--------
                //Finished
                return col;
            }

            ENDHLSL
        }
    }
}
