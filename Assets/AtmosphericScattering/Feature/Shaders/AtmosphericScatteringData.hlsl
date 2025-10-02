#ifndef ATMOSPHERIC_SCATTERING_DATA_H
#define ATMOSPHERIC_SCATTERING_DATA_H

#include "./AtmosphericScatteringUtils.hlsl"

CBUFFER_START(AtmosphereParams)
    float topHeight;
    float earthRadius;
    float3 earthCenter;
    float3 rayleighScatteringCoefficient;
    float rayleighHeight;
    float3 mieScatteringCoefficient;
    float3 mieAbsorptionCoefficient;
    float mieHeight;
    float3 ozoneAbsorptionCoefficient;
    float ozoneCenter;
    float ozoneWidth;
    float maxTangentLength;
    float mieG;

    float atmosphereIntensity;
    float atmosphereMultiScatteringIntensity;
CBUFFER_END

ScatteringParameters CollectParams()
{
    ScatteringParameters params;
    params.topHeight = topHeight;
    params.earthRadius = earthRadius;
    params.earthCenter = earthCenter;
    params.rayleighScatteringCoefficient = rayleighScatteringCoefficient;
    params.rayleighHeight = rayleighHeight;
    params.mieScatteringCoefficient = mieScatteringCoefficient;
    params.mieAbsorptionCoefficient = mieAbsorptionCoefficient;
    params.mieHeight = mieHeight;
    params.ozoneAbsorptionCoefficient = ozoneAbsorptionCoefficient;
    params.ozoneCenter = ozoneCenter;
    params.ozoneWidth = ozoneWidth;
    params.maxTangentLength = maxTangentLength;
    params.mieG = mieG;
    params.atmosphereIntensity = atmosphereIntensity;
    params.atmosphereMultiScatteringIntensity = atmosphereMultiScatteringIntensity;
    return params;
}

#endif