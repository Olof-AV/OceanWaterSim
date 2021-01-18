//-----------------------------------------------------------
//Location of this shader, within the browser in material GUI
Shader "Custom/FFT_Spectrum"
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

            //-------------------------
            //Parameters for our shader
            CBUFFER_START(UnityPerMaterial)

                //FFT parameters
                //float4 _PhillipsSpectrum_TexelSize;
                float _FFT_Size;
                float _FFT_Res;

                float _FFT_WaveHeightMult;
                float _FFT_WaveMinHeight;
                float _FFT_Directionality;

                float4 _FFT_Wind;

                float4 _FFT_GaussParams;
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

            //Improved canonical one liner
            //http://byteblacksmith.com/improvements-to-the-canonical-one-liner-glsl-rand-for-opengl-es-2-0/
            float random(const float2 input)
            {
                const float a = 12.9898f;
                const float b = 78.233f;
                const float c = 43758.5453f;
                const float dt = dot(input.xy, float2(a, b));
                const float sn = fmod(dt, 3.14f);
                return frac(sin(sn) * c);
            }

            //Gaussian rand based off the Box-Muller method
            float gaussianRand(const float2 input)
            {
                //Get two input values
                //clamp in log() input eliminates random freckles
                const float x1 = clamp(random(input), 0.0001f, 1.0f);
                const float x2 = clamp(random(input - 0.25f), 0.0001f, 1.0f);

                //Apply box muller
                return sqrt(-log(x1)) * (1.41421356237f * cos(TWO_PI * x2));
            }

            //Helper function for the Phillips spectrum
            //In the GPGPU FFT Ocean Simulation paper, the implementation differs a bit from Tessendorf's, how come? It does look better too
            float Phillips(const float kLength, const float L, const float kw_pow)
            {
                return (sqrt(_FFT_WaveHeightMult / pow(kLength, 4.0f))
                    * exp(-(1.0f / pow(kLength * L, 2.0f)))
                    * kw_pow
                    * exp(-pow(kLength, 2.0f) * pow(_FFT_WaveMinHeight, 2.0f))
                    );
            }

            //---------------
            //Fragment shader
            half4 ForwardPassFragment(Varyings input) : SV_Target
            {
                //----------
                //Initialise
                half4 col = 0.0f;
                const float2 windDir = normalize(_FFT_Wind.xy);
                const float windSpeed = _FFT_Wind.z;
                const float gravity = _FFT_Wind.w;
                const float L = (windSpeed * windSpeed) / gravity;

                const float2 k = TWO_PI * (input.positionCS.xy - (float2(_FFT_Res, _FFT_Res) * 0.5f)) / _FFT_Size;
                const float kLength = length(k);

                //----------
                //Positive K
                //X and Y
                {
                    //Temp part of the formula
                    const float kw_pow = pow(abs(dot(normalize(k), windDir)), _FFT_Directionality);

                    //-----------------------
                    //Apply formula 23 and 24
                    const float sqrtPhillips = Phillips(kLength, L, kw_pow);

                    //---------------------------
                    //Gaussian noise added on top
                    col.x = (0.70710678118f) * gaussianRand(k * _FFT_GaussParams.x) * sqrtPhillips;
                    col.y = (0.70710678118f) * gaussianRand(k * _FFT_GaussParams.y) * sqrtPhillips;
                }

                //----------
                //Negative K
                //Z and W
                {
                    //Temp part of the formula
                    const float kw_pow = pow(abs(dot(normalize(-k), windDir)), _FFT_Directionality);

                    //-----------------------
                    //Apply formula 23 and 24
                    const float sqrtPhillips = Phillips(kLength, L, kw_pow);

                    //---------------------------
                    //Gaussian noise added on top
                    col.z = (0.70710678118f) * gaussianRand(-k * _FFT_GaussParams.z) * sqrtPhillips;
                    col.w = (0.70710678118f) * gaussianRand(-k * _FFT_GaussParams.w) * sqrtPhillips;
                }

                //--------
                //Finished
                return col;
            }

            ENDHLSL
        }
    }
}
