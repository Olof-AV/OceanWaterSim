using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[System.Serializable]
public struct GerstnerWave
{
    [SerializeField] public float WaveAmplitude;
    [SerializeField] public float WaveFrequency;
    [SerializeField] [Range(0.0f, 1.0f)] public float WaveSharpness;

    [SerializeField] public Vector2 WindDirection;
    [SerializeField] public float WindSpeed;
}

public class WaveManager : MonoBehaviour
{
    //------------------------------------------------
    //Variables
    [Header("General")]
    [SerializeField] private float _waterInitialHeight;
    [SerializeField] private float _waterDensity;

    //Gerstner Parameters
    [Header("Gerstner Waves")]
    [SerializeField] private List<GerstnerWave> _wavesLowFreq = null;
    [SerializeField] private List<GerstnerWave> _wavesHighFreq = null;

    //Gerstner internal
    private ComputeBuffer _wavesBufferLowFreq = null;
    private ComputeBuffer _wavesBufferHighFreq = null;

    //FFT Parameters
    [Header("FFT Render Textures")]
    [SerializeField] private bool _alwaysUpdatePhillips = false;
    [SerializeField] private CustomRenderTexture _phillipsSpectrum = null;
    [SerializeField] private CustomRenderTexture _butterflyTexture = null;
    [SerializeField] private CustomRenderTexture _fourierAmps_Y = null;
    [SerializeField] private CustomRenderTexture _fourierAmps_X = null;
    [SerializeField] private CustomRenderTexture _fourierAmps_Z = null;
    [SerializeField] private CustomRenderTexture _finalDisplacement = null;
    [SerializeField] private ComputeShader _computeIFFT = null;

    [Header("FFT Phillips Settings")]
    [SerializeField] private float _fourierGridSize = 1000.0f;
    [SerializeField] private float _fourierResolution = 512.0f;
    private float _savedFourierResolution = 512.0f;

    [SerializeField] private float _waveHeightMult = 4.0f;
    [SerializeField] private float _waveMinHeight = 0.5f;

    [SerializeField] private Vector2 _windDirection = Vector2.zero;
    [SerializeField] private float _windSpeed = 10.0f;
    [SerializeField] private float _gravitationalConstant = 9.81f;

    [Header("FFT Randomisation Settings")]
    [SerializeField] private float _gaussianScaleRealPos = 1.0f;
    [SerializeField] private float _gaussianScaleImagPos = 1.0f;
    [SerializeField] private float _gaussianScaleRealNeg = 1.0f;
    [SerializeField] private float _gaussianScaleImagNeg = 1.0f;

    [Header("FFT Spectrum Settings")]
    [SerializeField] private float _fourierAmpSpeedMult = 2.0f;
    [SerializeField] private float _fourierDirectionality = 2.0f;

    [Header("FFT Displacement Settings")]
    [SerializeField] private float _displacementStrength_Y = 1.0f;
    [SerializeField] private float _displacementStrength_XZ = 1.0f;
    [SerializeField] private float _scaleFFT = 1.0f;

    //FFT Internal
    private RenderTexture _pingPong0 = null;
    private RenderTexture _pingPong1 = null;
    private RenderTexture _displacementY = null;
    private RenderTexture _displacementX = null;
    private RenderTexture _displacementZ = null;
    private int _computeKernelIndex = 0;
    private uint _computeThreadCount = 0;

    private int[] _bitReversedIndices = null;
    private ComputeBuffer _cbBitReversed = null;
    //------------------------------------------------

    //Sets up Gerstner waves, we mostly need to pass StructuredBuffers around so create those
    private void InitialiseGerstner()
    {
        //Low freq
        {
            //Invalid? Stop execution
            if (_wavesLowFreq == null) { return; }
            if (_wavesLowFreq.Count == 0) { return; }

            //Otherwise, create buffer
            _wavesBufferLowFreq = new ComputeBuffer(_wavesLowFreq.Count, 4 * 6, ComputeBufferType.Structured); //6 floats, each float is 4 bytes
            _wavesBufferLowFreq.SetData(_wavesLowFreq);
        }

        //High freq
        {
            //Invalid? Stop execution
            if (_wavesHighFreq == null) { return; }
            if (_wavesHighFreq.Count == 0) { return; }

            //Otherwise, create buffer
            _wavesBufferHighFreq = new ComputeBuffer(_wavesHighFreq.Count, 4 * 6, ComputeBufferType.Structured); //6 floats, each float is 4 bytes
            _wavesBufferHighFreq.SetData(_wavesHighFreq);
        }
    }

    //Helper to reset custom render textures
    private void ResetCustomRT(ref CustomRenderTexture crt, int width, int height, string propertyName = "", bool update = true)
    {
        //Invalid? Stop
        if(!crt) { return; }

        //Allow shaders to read the render texture, if a name is provided
        if(propertyName.Length > 0) { Shader.SetGlobalTexture(propertyName, crt); }

        //Reset size
        crt.Release();
        crt.width = width;
        crt.height = height;
        crt.Create();

        //Update for safety
        if(update)
        {
            crt.Initialize();
            crt.Update();
        }
    }

    //Helper to create render textures
    private void CreateRT(ref RenderTexture rt, int width, int height, string propertyName = "",
        RenderTextureFormat rtf = RenderTextureFormat.RGFloat,
        RenderTextureReadWrite rtrw = RenderTextureReadWrite.Linear,
        FilterMode fm = FilterMode.Point, TextureWrapMode twm = TextureWrapMode.Repeat)
    {
        //Create + set params
        rt = new RenderTexture(width, height, 0, rtf, rtrw);
        rt.enableRandomWrite = true;
        rt.filterMode = fm;
        rt.wrapMode = twm;
        rt.Create();

        //Expose to shaders if property name is provided
        if(propertyName.Length > 0) { rt.SetGlobalShaderProperty(propertyName); }
    }

    //Comparatively, FFT needs much more setup
    //We need to manually create new render textures, resize provided ones, compute the bit-reversed array...
    private void InitialiseFFT()
    {
        //Invalid? Stop
        if (!_phillipsSpectrum) { return; }
        if (!_butterflyTexture) { return; }
        if (!_fourierAmps_Y) { return; }
        if (!_fourierAmps_X) { return; }
        if (!_fourierAmps_Z) { return; }
        if (!_finalDisplacement) { return; }
        if (!_computeIFFT) { return; }

        //This is the common N size, needs to be a power of 2
        int sizeN = Mathf.RoundToInt(_fourierResolution);

        //Fix N size if necessary, can ONLY be powers of 2
        if (sizeN < 0 || Mathf.CeilToInt(Mathf.Log(sizeN, 2.0f)) != Mathf.FloorToInt(Mathf.Log(sizeN, 2.0f)))
        {
            sizeN = 256;
            _fourierResolution = 256.0f;
            Debug.LogError("Fourier Resolution was not a power of 2, reset to 256.");
        }
        _savedFourierResolution = _fourierResolution; //Fourier resolution not allowed to change past this point

        //Set data just to be sure
        UpdateDataFFT();

        //Phillips Spectrum
        {
            ResetCustomRT(ref _phillipsSpectrum, sizeN, sizeN, "_PhillipsSpectrum", true);
        }

        //Butterfly texture
        {
            int width = Mathf.RoundToInt(Mathf.Log10(_fourierResolution) / Mathf.Log10(2.0f)); //<- Log2 of size
            ResetCustomRT(ref _butterflyTexture, width, sizeN, "_ButterflyTex", true);
        }

        //Fourier amps, Y
        {
            ResetCustomRT(ref _fourierAmps_Y, sizeN, sizeN, update: false);
            ResetCustomRT(ref _fourierAmps_X, sizeN, sizeN, update: false);
            ResetCustomRT(ref _fourierAmps_Z, sizeN, sizeN, update: false);
        }

        //Final displacement
        {
            ResetCustomRT(ref _finalDisplacement, sizeN, sizeN, "_DisplacementFFT");
        }

        //Initialise IFFT stuff
        {
            //Render textures
            {
                CreateRT(ref _pingPong0, sizeN, sizeN);
                CreateRT(ref _pingPong1, sizeN, sizeN);
                CreateRT(ref _displacementY, sizeN, sizeN, "_DisplacementFFT_Y");
                CreateRT(ref _displacementX, sizeN, sizeN, "_DisplacementFFT_X");
                CreateRT(ref _displacementZ, sizeN, sizeN, "_DisplacementFFT_Z");
            }

            //Compute shader
            _computeKernelIndex = _computeIFFT.FindKernel("IFFT");
            _computeIFFT.GetKernelThreadGroupSizes(_computeKernelIndex, out _computeThreadCount, out uint temp1, out uint temp2);

            //Bit reversal array creation
            {
                //Initialise
                int maxSize = Mathf.RoundToInt(Mathf.Log10(sizeN) / Mathf.Log10(2.0f)); //<- Log2 of size
                _bitReversedIndices = new int[sizeN];
                _bitReversedIndices[0] = 0;

                //Temporary values
                int counter = 1;
                int loopCount = 0;

                //The max number of loops required to fill the array is Log2 of size
                while (loopCount < maxSize)
                {
                    //For ALL previously filled in numbers in the array, take them and add SIZE / 2, then SIZE / 4, then SIZE / 8...,
                    //until SIZE / SIZE, in which case you'll add 1 to the previous half of the array and finish the algorithm
                    for (int i = 0; i < counter; ++i)
                    {
                        _bitReversedIndices[counter + i] = _bitReversedIndices[i] + sizeN / (int)(Mathf.Pow(2.0f, loopCount + 1.0f));
                    }

                    //Increment amount of filled indices
                    counter += counter;

                    //We completed one full loop
                    loopCount++;
                }

                //Set data in compute shader
                _cbBitReversed = new ComputeBuffer(sizeN, 4, ComputeBufferType.Structured); //Stride 4 because 1 int = 4 bytes
                _cbBitReversed.SetData(_bitReversedIndices);
                Shader.SetGlobalBuffer("_BitReversedIndices", _cbBitReversed);
            }
        }
    }

    //Initialise
    private void Start()
    {
        //--------------
        //Gerstner Waves
        {
            InitialiseGerstner();
        }
        
        //---------
        //FFT waves
        {
            InitialiseFFT();
        }
    }

    //Update shader parameters here according to waves list (StructuredBuffer)
    void UpdateGerstnerData()
    {
        //Low freq
        {
            //Invalid? Stop execution
            if (_wavesLowFreq == null) { return; }
            if (_wavesLowFreq.Count == 0) { return; }

            //Update buffer data
            _wavesBufferLowFreq.SetData(_wavesLowFreq);

            //Update our shader data
            Shader.SetGlobalBuffer("_GerstnerWavesLowFreq", _wavesBufferLowFreq);
            Shader.SetGlobalInt("_GerstnerWavesLowFreqCount", _wavesLowFreq.Count);
        }

        //High freq
        {
            //Invalid? Stop execution
            if (_wavesHighFreq == null) { return; }
            if (_wavesHighFreq.Count == 0) { return; }

            //Update buffer data
            _wavesBufferHighFreq.SetData(_wavesHighFreq);

            //Update our shader data
            Shader.SetGlobalBuffer("_GerstnerWavesHighFreq", _wavesBufferHighFreq);
            Shader.SetGlobalInt("_GerstnerWavesHighFreqCount", _wavesHighFreq.Count);
        }
    }

    //Update but for FFT
    void UpdateDataFFT()
    {
        //Variables
        {
            //First, fix any unsafe values
            float threshold = 0.001f;
            _waveHeightMult = Mathf.Max(threshold, _waveHeightMult);
            _windSpeed = Mathf.Max(threshold, _windSpeed);
            _gravitationalConstant = Mathf.Max(threshold, _gravitationalConstant);
            _fourierDirectionality = Mathf.Max(threshold, _fourierDirectionality);
            _fourierResolution = _savedFourierResolution; //FFT resolution not allowed to change while running

            //Apply new values
            Shader.SetGlobalFloat("_FFT_Size", _fourierGridSize);
            Shader.SetGlobalFloat("_FFT_Res", _fourierResolution);

            Shader.SetGlobalFloat("_FFT_WaveHeightMult", _waveHeightMult);
            Shader.SetGlobalFloat("_FFT_WaveMinHeight", _waveMinHeight);

            Shader.SetGlobalVector("_FFT_Wind", new Vector4(_windDirection.x, _windDirection.y, _windSpeed, _gravitationalConstant));

            Shader.SetGlobalVector("_FFT_GaussParams", new Vector4(_gaussianScaleRealPos, _gaussianScaleImagPos, _gaussianScaleRealNeg, _gaussianScaleImagNeg));

            Shader.SetGlobalFloat("_FFT_FourierAmpSpeedMult", _fourierAmpSpeedMult);
            Shader.SetGlobalFloat("_FFT_Directionality", _fourierDirectionality);

            Shader.SetGlobalFloat("_FFT_DisplacementStrength_Y", _displacementStrength_Y);
            Shader.SetGlobalFloat("_FFT_DisplacementStrength_XZ", _displacementStrength_XZ);
            Shader.SetGlobalFloat("_FFT_Scale", _scaleFFT);
        }

        //If set to always update phillips spectrum, update
        //Mostly for debug purposes
        if(_phillipsSpectrum && _alwaysUpdatePhillips)
        {
            _phillipsSpectrum.Initialize();
            _phillipsSpectrum.Update();
        }

        //Update time dependent fourier amps
        if(_fourierAmps_Y && _fourierAmps_X && _fourierAmps_Z)
        {
            _fourierAmps_Y.Initialize();
            _fourierAmps_Y.Update();

            _fourierAmps_X.Initialize();
            _fourierAmps_X.Update();

            _fourierAmps_Z.Initialize();
            _fourierAmps_Z.Update();
        }
    }

    //Performs IFFT required to obtain height maps
    void PerformIFFT(RenderTexture sourceAmps, RenderTexture target)
    {
        //Invalid? Stop
        if(!sourceAmps) { return; }
        if(!target) { return; }
        if(!_computeIFFT) { return; }

        //Have something ready for ping pong1
        Graphics.Blit(sourceAmps, _pingPong0);

        //Setup compute shader with appropriate params
        int res = (int)_fourierResolution;
        int threadGroups = res / (int)_computeThreadCount;
        int max = Mathf.RoundToInt(Mathf.Log10(res) / Mathf.Log10(2.0f)); //<- Log2 of size
        bool isPingPong = false;
        _computeIFFT.SetTexture(_computeKernelIndex, "Texture0", _pingPong0);
        _computeIFFT.SetTexture(_computeKernelIndex, "Texture1", _pingPong1);
        _computeIFFT.SetTexture(_computeKernelIndex, "Displacement", target);
        _computeIFFT.SetBool("isPermutation", false);
        _computeIFFT.SetFloat("resolution_N", _fourierResolution);

        //1D IFFT on the horizontal
        {
            //Initialise
            _computeIFFT.SetBool("isHorizontal", true);
            _computeIFFT.SetTextureFromGlobal(_computeKernelIndex, "Butterfly", "_ButterflyTex");
            _computeIFFT.SetInts("bitReversedIndices", _bitReversedIndices);

            //Run through IFFT stages
            for(int i = 0; i < max; ++i)
            {
                //Set params
                _computeIFFT.SetBool("isPingPong", isPingPong);
                _computeIFFT.SetInt("stageFFT", i);

                //Run compute shader
                _computeIFFT.Dispatch(_computeKernelIndex, threadGroups, threadGroups, 1);

                //Invert ping pong
                isPingPong = !isPingPong;
            }
        }

        //1D FFT on the vertical
        {
            //Initialise
            _computeIFFT.SetBool("isHorizontal", false);

            //Run through IFFT stages
            for (int i = 0; i < max; ++i)
            {
                //Set params
                _computeIFFT.SetBool("isPingPong", isPingPong);
                _computeIFFT.SetInt("stageFFT", i);

                //Run compute shader
                _computeIFFT.Dispatch(_computeKernelIndex, threadGroups, threadGroups, 1);

                //Invert ping pong
                isPingPong = !isPingPong;
            }
        }

        //Inversion/permutation
        {
            //Now, permute
            _computeIFFT.SetBool("isPermutation", true);

            //Run compute shader
            _computeIFFT.Dispatch(_computeKernelIndex, threadGroups, threadGroups, 1);
        }
    }

    //Update the data
    private void LateUpdate()
    {
        //Gerstner
        {
            UpdateGerstnerData();
        }

        //FFT
        if(_finalDisplacement)
        {
            //Have input params + custom render textures updated
            UpdateDataFFT();

            //Perform IFFT on the amplitudes, for each axis
            PerformIFFT(_fourierAmps_Y, _displacementY);
            PerformIFFT(_fourierAmps_X, _displacementX);
            PerformIFFT(_fourierAmps_Z, _displacementZ);

            //The final displacement is updated, to reflect the IFFT result
            _finalDisplacement.Initialize();
            _finalDisplacement.Update();
        }
    }

    //Clean up the buffer (this is required)
    private void OnDestroy()
    {
        //--------
        //Gerstner
        {
            if (_wavesBufferLowFreq != null) { _wavesBufferLowFreq.Release(); }
            if (_wavesBufferHighFreq != null) { _wavesBufferHighFreq.Release(); }
        }

        //---
        //FFT
        {
            if(_cbBitReversed != null) { _cbBitReversed.Release(); }
            if(_pingPong0 != null) { _pingPong0.Release(); }
            if(_pingPong1 != null) { _pingPong1.Release(); }
            if(_displacementY != null) { _displacementY.Release(); }
            if(_displacementX != null) { _displacementX.Release(); }
            if(_displacementZ != null) { _displacementZ.Release(); }
        }
    }

    //-------
    //Getters
    public float GetWaterInitialHeight()
    {
        return _waterInitialHeight;
    }

    public float GetWaterDensity()
    {
        return _waterDensity;
    }

    public List<GerstnerWave> GetGerstnerLowFreq()
    {
        return _wavesLowFreq;
    }

    public List<GerstnerWave> GetGerstnerHighFreq()
    {
        return _wavesHighFreq;
    }

    public float GetFourierResolution()
    {
        return _fourierResolution;
    }

    public float GetDisplacementStrengthXZ()
    {
        return _displacementStrength_XZ;
    }

    public float GetDisplacementStrengthY()
    {
        return _displacementStrength_Y;
    }

    public float GetScaleFFT()
    {
        return _scaleFFT;
    }
}