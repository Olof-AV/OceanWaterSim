using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Buoyancy : MonoBehaviour
{
    //---------
    //Variables
    [Header("General")]
    [SerializeField] private WaveManager _waveManager = null;
    [SerializeField] private Rigidbody _rigidBody = null;

    [Header("Buoyancy")]
    [SerializeField] private List<Transform> _buoyancyPoints = null;
    [SerializeField] private float _totalVolume;

#if UNITY_EDITOR
    [SerializeField] private bool _drawDebugPoints = false;
    [SerializeField] private bool _drawDebugWaveHeight = false;
#endif

    //Cache
    private List<GerstnerWave> _lowFreqWaves = null;
    private float _gravityMag;

    //---------
    //Functions
    private void Start()
    {
        //Cache
        _gravityMag = Physics.gravity.magnitude;
        _waveManager = (_waveManager) ? _waveManager : FindObjectOfType<WaveManager>();

        if(_waveManager)
        {
            _lowFreqWaves = _waveManager.GetGerstnerLowFreq();
        }
    }

    //Function to obtain approximate "corrected" position
    private void GetWaveForPos(Vector3 worldPos, float waterInitialHeight, out float waterHeight, out Vector3 normal)
    {
        //Initialise
        Vector3 tempPos = worldPos;
        Vector3 pos1 = Vector3.zero;
        Vector3 pos2 = Vector3.zero;

        //-------------------------
        //Obtain the first position
        {
            //Computing first pos
            tempPos.y = waterInitialHeight;
            DoGerstnerTransform(tempPos, out Vector3 totalDisp, _lowFreqWaves);
            pos1 = tempPos + totalDisp;

            //Move temp pos backwards to go to our second point
            tempPos -= totalDisp;
        }

        //-----------------------------
        //Obtain the secondary position
        {
            //Computing second pos
            tempPos.y = waterInitialHeight;
            DoGerstnerTransform(tempPos, out Vector3 totalDisp, _lowFreqWaves);
            pos2 = tempPos + totalDisp;
        }

        //----------------------------------------------------
        //From the two positions, obtain the final wave height
        {
            //Obtain projected point between the two computed positions
            //This is merely an APPROXIMATION for the real water height for the given position
            Vector3 from1To2 = (pos2 - pos1).normalized;
            Vector3 pos3 = Vector3.Dot((worldPos - pos1), from1To2) * from1To2 + pos1;

            //Debug
#if UNITY_EDITOR
            if (_drawDebugWaveHeight)
            {
                Debug.DrawLine(worldPos, pos1, Color.green, 0.0f, false);
                Debug.DrawLine(worldPos, pos2, Color.green, 0.0f, false);
                Debug.DrawLine(pos1, pos2, Color.cyan, 0.0f, false);
                Debug.DrawLine(worldPos, pos3, Color.red, 0.0f, false);
            }
#endif

            //Finished
            waterHeight = pos3.y;
            DoGerstnerNormalVectors(pos3, out normal, _lowFreqWaves);
        }
    }

    //Update
    private void FixedUpdate()
    {
        //Invalid? Stop execution
        if(!_waveManager) { return; }
        if(_buoyancyPoints.Count == 0) { return; }
        if(!_rigidBody) { return; }

        //Cache
        float waterDensity = _waveManager.GetWaterDensity();
        float waterInitialHeight = _waveManager.GetWaterInitialHeight();
        _lowFreqWaves = _waveManager.GetGerstnerLowFreq();

        //Go through the buoyancy points, test whether to add upwards force based on Archimedes' Principle or not
        for (int i = 0; i < _buoyancyPoints.Count; ++i)
        {
            //Transform using Gerstner
            Vector3 worldPos = _buoyancyPoints[i].position;
            float pointHeight = worldPos.y;
            GetWaveForPos(worldPos, waterInitialHeight, out float waterHeight, out Vector3 normal);

            bool isBelowWater = waterHeight > pointHeight;

            //Check if our point is above or below water
            if (isBelowWater)
            {
                _rigidBody.AddForceAtPosition(-waterDensity * _totalVolume * (1.0f / _buoyancyPoints.Count) * _gravityMag * normal * Time.fixedDeltaTime,
                    _buoyancyPoints[i].position,
                    ForceMode.Force);
            }

            //Debug to show buoyancy points
            #if UNITY_EDITOR
            if(_drawDebugPoints)
            {
                Debug.DrawLine(transform.position, _buoyancyPoints[i].position, (isBelowWater) ? Color.green : Color.red, 0.0f, false);
            }
        #endif
        }
    }

    //Adapted from Gerstner.hlsl
    private void DoGerstnerTransform(in Vector3 worldPos, out Vector3 totalDisp, in List<GerstnerWave> wavesBuffer)
    {
        //For each wave, apply gerstner wave formula
        totalDisp = Vector3.zero;
        int wavesCount = wavesBuffer.Count;
        for (int i = 0; i < wavesCount; ++i)
        {
            //Cache wave
            GerstnerWave wave = wavesBuffer[i];

            //Wind dir can be 0 vector
            Vector2 windDir = (wave.WindDirection == Vector2.zero) ? Vector2.zero : (wave.WindDirection).normalized;

            //Obtain sharpness
            float sharpness = Mathf.LerpUnclamped(0.0f, 1.0f / Mathf.Max(0.001f, wave.WaveFrequency * wave.WaveAmplitude * wavesCount), wave.WaveSharpness);

            //This is the common input for sin/cos functions
            float waveInput = (Vector2.Dot(windDir, new Vector2(worldPos.x, worldPos.z)) * wave.WaveFrequency + Time.time * wave.WindSpeed);
            float cosWave = Mathf.Cos(waveInput);
            float sinWave = Mathf.Sin(waveInput);

            //Compute displacement
            Vector3 displacement = new Vector3(
                sharpness * wave.WaveAmplitude * windDir.x * cosWave,
                wave.WaveAmplitude * sinWave,
                sharpness * wave.WaveAmplitude * windDir.y * cosWave);

            //Add to total
            totalDisp += displacement;
        }
    }

    //Adapted from Gerstner.hlsl
    void DoGerstnerNormalVectors(Vector3 worldPos, out Vector3 normal,
        in List<GerstnerWave> wavesBuffer)
    {
        Vector3 binormal = Vector3.zero;
        Vector3 tangent = Vector3.zero;

        //For each wave, compute normal
        for (int j = 0; j < wavesBuffer.Count; ++j)
        {
            //Cache wave
            GerstnerWave wave = wavesBuffer[j];

            //Wind dir can be 0 vector
            Vector2 windDir = (wave.WindDirection == Vector2.zero) ? Vector2.zero : (wave.WindDirection).normalized;

            //Obtain sharpness
            float sharpness = Mathf.LerpUnclamped(0.0f, 1.0f / Mathf.Max(0.001f, wave.WaveFrequency * wave.WaveAmplitude * wavesBuffer.Count), wave.WaveSharpness);

            //This is the common input for sin/cos functions
            float waveInput = Vector2.Dot(windDir, new Vector2(worldPos.x, worldPos.z)) * wave.WaveFrequency + Time.time * wave.WindSpeed;
            float cosWave = Mathf.Cos(waveInput);
            float sinWave = Mathf.Sin(waveInput);

            //Add to binormal
            binormal += new Vector3(
                sharpness * (windDir.x * windDir.x) * wave.WaveFrequency * wave.WaveAmplitude * sinWave,
                sharpness * windDir.x * windDir.y * wave.WaveFrequency * wave.WaveAmplitude * sinWave,
                windDir.x * wave.WaveFrequency * wave.WaveAmplitude * cosWave
                );

            //Add to tangent
            tangent += new Vector3(
                sharpness * windDir.x * windDir.y * wave.WaveFrequency * wave.WaveAmplitude * sinWave,
                sharpness * (windDir.y * windDir.y) * wave.WaveFrequency * wave.WaveAmplitude * sinWave,
                windDir.y * wave.WaveFrequency * wave.WaveAmplitude * cosWave);
        }

        //Rebalance
        binormal = new Vector3(1.0f - binormal.x, -binormal.y, binormal.z);
        tangent = new Vector3(-tangent.x, 1.0f - tangent.y, tangent.z);

        //Adjust to our coordinate system
        binormal = Vector3.Normalize(new Vector3(binormal.x, binormal.z, binormal.y));
        tangent = Vector3.Normalize(new Vector3(tangent.x, tangent.z, tangent.y));

        //Obtain normal vector from cross
        normal = Vector3.Cross(binormal, tangent);
    }
}
