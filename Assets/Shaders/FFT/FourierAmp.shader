//-----------------------------------------------------------
//Location of this shader, within the browser in material GUI
Shader "Custom/FFT_FourierAmp"
{
    //--------------------
    //Tweakable properties
    Properties
    {
        //---------------------
        //X, Y or Z
        [Toggle(X_AXIS)] _X_Axis("Compute X axis?", Float) = 0
        [Toggle(Z_AXIS)] _Z_Axis("Compute Z axis?", Float) = 0
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

            // -------------------------------------
            // Custom keywords
            #pragma shader_feature X_AXIS
            #pragma shader_feature Z_AXIS

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
            TEXTURE2D(_PhillipsSpectrum); //Spectrum
            SAMPLER(sampler_PhillipsSpectrum);

            //-------------------------
            //Parameters for our shader
            CBUFFER_START(UnityPerMaterial)

                //FFT parameters
                float4 _PhillipsSpectrum_ST;
                //float4 _PhillipsSpectrum_TexelSize;
                float _FFT_Size;
                float _FFT_Res;

                float4 _FFT_Wind;

                float _FFT_FourierAmpSpeedMult;
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

            //https://www.mathsisfun.com/numbers/complex-numbers.html
            float2 compConj(const float2 a)
            {
                return float2(a.x, -a.y);
            }

            //https://www.mathsisfun.com/numbers/complex-numbers.html
            float2 compMul(const float2 a, const float2 b)
            {
                return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
            }

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

                const float2 k = TWO_PI * (input.positionCS.xy - (float2(_FFT_Res, _FFT_Res) * 0.5f)) / _FFT_Size;
                const float kLength = length(k);
                const float dispersionTime = sqrt(_FFT_Wind.w * kLength) * (_Time.y * _FFT_FourierAmpSpeedMult);

                const float4 sampledSpectrum = _PhillipsSpectrum.Load(int3(input.positionCS.xy, 0));

                //----------------------------------
                //Compute h(k, t) through formula 26
                const float2 result = compMul(sampledSpectrum.xy, compExp(dispersionTime)) + compMul(compConj(sampledSpectrum.zw), compExp(-dispersionTime));

                //-----------------------------------------------------------------------------------
                //Depending on the axis, we might still need to multiply by an extra imaginary number
                //or we can leave the result as is
            #ifdef X_AXIS
                col.xy = compMul(float2(0.0f, -k.x / kLength), result); //X
            #elif Z_AXIS
                col.xy = compMul(float2(0.0f, -k.y / kLength), result); //Z
            #else
                col.xy = result; //Y
            #endif

                //--------
                //Finished
                return col;
            }

            ENDHLSL
        }
    }
}
