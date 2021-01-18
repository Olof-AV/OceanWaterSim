using System.Collections;
using System.Collections.Generic;
using UnityEngine;

//Struct used for the compute shader
public struct TestPoint
{
    public Vector3 _pos;
    public Vector3 _waterNormal;
}

public class FFT_Buoyancy : MonoBehaviour
{
    //---------
    //Variables
    [Header("General")]
    [SerializeField] private WaveManager _waveManager = null;
    [SerializeField] private Rigidbody _rigidBody = null;

    [Header("Buoyancy")]
    [SerializeField] private List<Transform> _buoyancyPoints = null;
    [SerializeField] private float _totalVolume;
    [SerializeField] private ComputeShader _computeShader;

#if UNITY_EDITOR
    [SerializeField] private bool _drawDebugPoints = false;
    [SerializeField] private bool _drawDebugWaveHeight = false;
#endif

    //Cache + buffers
    private float _gravityMag;
    private int _csIndex;
    private uint _csGroupSize;
    private TestPoint[] _cbData;
    private ComputeBuffer _cb;

    //---------
    //Functions
    private void Start()
    {
        //If no compute shader, can't initialise
        if(!_computeShader) { return; }

        //Cache
        _gravityMag = Physics.gravity.magnitude;
        _waveManager = (_waveManager) ? _waveManager : FindObjectOfType<WaveManager>();
        _csIndex = _computeShader.FindKernel("Buoyancy");
        _computeShader.GetKernelThreadGroupSizes(_csIndex, out _csGroupSize, out uint temp, out uint temp2);

        //Creating compute buffer
        _cbData = new TestPoint[_buoyancyPoints.Count];
        for(int i = 0; i < _buoyancyPoints.Count; ++i)
        {
            TestPoint newPoint = new TestPoint();
            newPoint._pos = _buoyancyPoints[i].position;
            newPoint._waterNormal = Vector3.up;
            _cbData[i] = newPoint;
        }
        _cb = new ComputeBuffer(_buoyancyPoints.Count, 24); //24 because 4 * 6
        _cb.SetData(_cbData);
    }

    //Update
    private void FixedUpdate()
    {
        //Invalid? Stop execution
        if (!_waveManager) { return; }
        if (_buoyancyPoints.Count == 0) { return; }
        if (!_rigidBody) { return; }
        if(!_computeShader) { return; }

        //Cache
        float waterDensity = _waveManager.GetWaterDensity();
        float waterInitialHeight = _waveManager.GetWaterInitialHeight();
        float sizeN = _waveManager.GetFourierResolution();
        float displacementStrengthY = _waveManager.GetDisplacementStrengthY();
        float displacementStrengthXZ = _waveManager.GetDisplacementStrengthXZ();
        float scaleFFT = _waveManager.GetScaleFFT();

        //Update and set data
        for(int i = 0; i < _buoyancyPoints.Count; ++i)
        {
            _cbData[i]._pos = _buoyancyPoints[i].position;
        }
        _cb.SetData(_cbData);
        _computeShader.SetFloat("sizeN", sizeN);
        _computeShader.SetFloat("displacementStrengthY", displacementStrengthY);
        _computeShader.SetFloat("displacementStrengthXZ", displacementStrengthXZ);
        _computeShader.SetFloat("scaleFFT", scaleFFT);
        _computeShader.SetFloat("waterInitialHeight", waterInitialHeight);
        _computeShader.SetTextureFromGlobal(_csIndex, "_Displacement", "_DisplacementFFT");
        _computeShader.SetBuffer(_csIndex, "Results", _cb);

        //Run compute shader for all buoyancy test points
        _computeShader.Dispatch(_csIndex, Mathf.CeilToInt((float)_buoyancyPoints.Count / (float)_csGroupSize), 1, 1);

        //Get data back
        _cb.GetData(_cbData);

        //For each point, determine how to apply buoyancy formula
        for(int i = 0; i <_buoyancyPoints.Count; ++i)
        {
            //Transform using Gerstner
            Vector3 worldPos = _buoyancyPoints[i].position;
            bool isBelowWater = _cbData[i]._pos.y > worldPos.y;

            //Check if our point is above or below water
            if (isBelowWater)
            {
                _rigidBody.AddForceAtPosition(waterDensity * _totalVolume * (1.0f / _buoyancyPoints.Count) * _gravityMag * _cbData[i]._waterNormal * Time.fixedDeltaTime,
                    _buoyancyPoints[i].position,
                    ForceMode.Force);
            }

            //Debug to show buoyancy points
        #if UNITY_EDITOR
            if (_drawDebugPoints)
            {
                Debug.DrawLine(transform.position, _buoyancyPoints[i].position, (isBelowWater) ? Color.green : Color.red, 0.0f, false);
            }

            if (_drawDebugWaveHeight)
            {
                Debug.DrawLine(worldPos, _cbData[i]._pos, Color.cyan, 0.0f, false);
            }
#endif
        }
    }

    //Clean after ourselves
    private void OnDestroy()
    {
        if(_cb != null) { _cb.Release(); }
    }
}
