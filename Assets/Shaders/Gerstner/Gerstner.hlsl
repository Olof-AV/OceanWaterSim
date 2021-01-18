//----------------------------
//Transferred from WaveManager
struct GerstnerWave
{
    float WaveAmplitude;
    float WaveFrequency;
    float WaveSharpness;
    
    float2 WindDirection;
    float WindSpeed;
};

//-------------------------------
//The Gerstner displacement logic
//Based off Water Sim with Cg
void DoGerstnerDisplacement(inout float3 worldPos, const in float time,
        const uniform StructuredBuffer<GerstnerWave> wavesBuffer, const uniform int wavesCount)
{
    //For each wave, apply gerstner wave formula
    float3 totalDisp = 0.0f;
    for (int i = 0; i < wavesCount; ++i)
    {
        //Cache wave
        const GerstnerWave wave = wavesBuffer[i];
        
        //Wind dir can be 0 vector
        const float2 windDir = (wave.WindDirection == 0.0f) ? 0.0f : normalize(wave.WindDirection);
        
        //Obtain sharpness
        const float sharpness = lerp(0.0f, 1.0f / max(0.001f, wave.WaveFrequency * wave.WaveAmplitude * wavesCount), wave.WaveSharpness);
        
        //This is the common input for sin/cos functions
        const float waveInput = dot(windDir, worldPos.xz) * wave.WaveFrequency + time * wave.WindSpeed;
        const float cosWave = cos(waveInput);
        const float sinWave = sin(waveInput);
        
        //Compute displacement
        const float3 displacement = float3(
            sharpness * wave.WaveAmplitude * windDir.x * cosWave,
            wave.WaveAmplitude * sinWave,
            sharpness * wave.WaveAmplitude * windDir.y * cosWave);
        
        //Add to total
        totalDisp += displacement;
    }
    
    //ONLY WHEN FINISHED, add total delta to position
    worldPos += totalDisp;
}

//----------------------------------------------
//Compute normal vectors off partial derivatives
//Based off GPU Gems
void DoGerstnerNormalVectors(const in float3 worldPos, const in float time, inout float3 binormal, inout float3 tangent,
        const uniform StructuredBuffer<GerstnerWave> wavesBuffer, const uniform int wavesCount)
{
    //For each wave, compute normal
    for (int j = 0; j < wavesCount; ++j)
    {
        //Cache wave
        const GerstnerWave wave = wavesBuffer[j];
        
        //Wind dir can be 0 vector
        const float2 windDir = (wave.WindDirection == 0.0f) ? 0.0f : normalize(wave.WindDirection);
        
        //Obtain sharpness
        const float sharpness = lerp(0.0f, 1.0f / max(0.001f, wave.WaveFrequency * wave.WaveAmplitude * wavesCount), wave.WaveSharpness);
        
        //This is the common input for sin/cos functions
        const float waveInput = wave.WaveFrequency * dot(windDir, worldPos.xz) + wave.WindSpeed * time;
        const float cosWave = cos(waveInput);
        const float sinWave = sin(waveInput);
        
        //Add to binormal
        binormal += float3(
            sharpness * (windDir.x * windDir.x) * wave.WaveFrequency * wave.WaveAmplitude * sinWave,
            sharpness * windDir.x * windDir.y * wave.WaveFrequency * wave.WaveAmplitude * sinWave,
            windDir.x * wave.WaveFrequency * wave.WaveAmplitude * cosWave
            );
        
        //Add to tangent
        tangent += float3(
            sharpness * windDir.x * windDir.y * wave.WaveFrequency * wave.WaveAmplitude * sinWave,
            sharpness * (windDir.y * windDir.y) * wave.WaveFrequency * wave.WaveAmplitude * sinWave,
            windDir.y * wave.WaveFrequency * wave.WaveAmplitude * cosWave);
    }
}

//---------------------------------
//The Gerstner functionality proper
void DoGerstner(inout float3 worldPos, const in float time, inout float3 normalWS, inout float3 binormalWS, inout float3 tangentWS,
        const uniform StructuredBuffer<GerstnerWave> gerstnerWavesLowFreq, const uniform int gerstnerWavesLowFreqCount,
        const uniform StructuredBuffer<GerstnerWave> gerstnerWavesHighFreq, const uniform int gerstnerWavesHighFreqCount)
{
    //We use low and high freq groups as recommended in "From Shore to Horizon"
    //Apply vertex displacement for low freq group
    DoGerstnerDisplacement(worldPos, time, gerstnerWavesLowFreq, gerstnerWavesLowFreqCount);

    //Apply normal vector formulas for low freq group
    DoGerstnerNormalVectors(worldPos, time, binormalWS, tangentWS, gerstnerWavesLowFreq, gerstnerWavesLowFreqCount);
    
    //Apply vertex displacement for high freq group
    DoGerstnerDisplacement(worldPos, time, gerstnerWavesHighFreq, gerstnerWavesHighFreqCount);

    //Apply normal vector formulas for high freq group
    DoGerstnerNormalVectors(worldPos, time, binormalWS, tangentWS, gerstnerWavesHighFreq, gerstnerWavesHighFreqCount);
    
    //Rebalance
    binormalWS = float3(1.0f - binormalWS.x, -binormalWS.y, binormalWS.z);
    tangentWS = float3(-tangentWS.x, 1.0f - tangentWS.y, tangentWS.z);
    
    //Adjust to our coordinate system
    binormalWS = normalize(float3(binormalWS.x, binormalWS.z, binormalWS.y));
    tangentWS = normalize(float3(tangentWS.x, tangentWS.z, tangentWS.y));
    
    //Obtain normal vector from cross
    //NOTE: LEFT HANDED CROSS SO REVERSE OF GPU GEMS?
    normalWS = cross(tangentWS, binormalWS);
}