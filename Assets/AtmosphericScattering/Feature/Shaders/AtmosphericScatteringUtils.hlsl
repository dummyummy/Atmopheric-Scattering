#ifndef ATMOSPHERIC_SCATTERING_UTILS_H
#define ATMOSPHERIC_SCATTERING_UTILS_H

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"

#define MAX_STEPS 64.0

struct ScatteringParameters
{
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
};

float3 GetScaledWorldPosition(float3 worldPos)
{
    return worldPos * 0.005;
}

inline float GetHeight(in ScatteringParameters params, float3 p)
{
    return length(p - params.earthCenter) - params.earthRadius;
}

float3 RayleighScattering(in ScatteringParameters params, float h)
{
    return params.rayleighScatteringCoefficient * exp(-h / params.rayleighHeight);
}

float RayleighPhase(in ScatteringParameters params, float cosTheta)
{
    const float c = 3.0f * rcp(16.0f * PI);
    return c * (1.0f + cosTheta * cosTheta);
}

float3 MieScattering(in ScatteringParameters params, float h)
{
    return params.mieScatteringCoefficient * exp(-h / params.mieHeight);
}

float MiePhase(in ScatteringParameters params, float cosTheta)
{
    const float c = 3.0f * rcp(8.0f * PI);
    float g2 = params.mieG * params.mieG;
    float cosTheta2 = cosTheta * cosTheta;
    return c * (1.0f - g2) * (1 + cosTheta2) * rcp((2.0f + g2) * pow(1.0f + g2 - 2.0f * params.mieG * cosTheta, 1.5f));
}

float3 MieAbsorption(in ScatteringParameters params, float h)
{
    return params.mieAbsorptionCoefficient * exp(-h / params.mieHeight);
}

float3 OzoneAbsorption(in ScatteringParameters params, float h)
{
    return params.ozoneAbsorptionCoefficient * saturate(1.0f - (h - params.ozoneCenter) * rcp(params.ozoneWidth));
}

float3 Scattering(in ScatteringParameters params, float h, float cosTheta)
{
    float3 rayleigh = RayleighScattering(params, h) * RayleighPhase(params, cosTheta);
    float3 mie = MieScattering(params, h) * MiePhase(params, cosTheta);
    return rayleigh + mie;
}

// only for precomputing transmittance
float3 Transmittance(in ScatteringParameters params, float3 src, float3 dst)
{
    const float INV_STEP = rcp(MAX_STEPS);
    float ds = length(dst - src) * INV_STEP;
    float3 trans = 0.0f;

    for (float i = 0.0; i < MAX_STEPS; i += 1.0)
    {
        float3 p = lerp(src, dst, (i + 0.5f) * INV_STEP);
        float h = GetHeight(params, p);
        float3 scattering = RayleighScattering(params, h) + MieScattering(params, h);
        float3 absorption = MieAbsorption(params, h) + OzoneAbsorption(params, h);
        trans += scattering + absorption;
    }

    return exp(-trans * ds);
}

void GetLocalFrame(float3 up, out float3 right, out float3 forward)
{
    right = abs(up.y > 0.5f) ? float3(1.0f, 0.0f, 0.0f) : float3(0.0f, 1.0f, 0.0f);
    forward = normalize(cross(up, right));
    right = normalize(cross(forward, up));
}

float2 GetLocalXY(float u)
{
    u = 4.0 * u;
    float range = floor(u);
    float x = (range == 0.0 || range == 2.0) ? 1.0 - frac(u) : frac(u);
    float y = (range == 0.0 || range == 2.0) ? frac(u) : 1.0 - frac(u);
    x = (range == 1.0 || range == 2.0) ? -x : x;
    y = (range == 2.0 || range == 3.0) ? -y : y;
    return float2(x, y);
}

float GetLocalU(float2 xy)
{
    float t = abs(xy.x) + abs(xy.y);
    xy = t == 0.0 ? 0.0 : xy / t;
    float range = xy.y > 0.0 ? 0.0 : 2.0;
    range += xy.x * xy.y > 0.0 ? 1.0 - abs(xy.x) : 1.0 + abs(xy.x);
    return range * 0.25f;
}

// dir must be normalized
bool HitEarth(in ScatteringParameters params, float3 p, float3 dir)
{
    float3 po = params.earthCenter - p;
    float t = dot(po, dir);
    float3 q = p + dir * t;
    return t > 0.0f && GetHeight(params, q) < 0.0f;
}

// Must ensure input ray hits the earth
float GetDistToEarth(in ScatteringParameters params, float h, float cosTheta)
{
    float bottomRadius = params.earthRadius;
    float radius = h + bottomRadius;
    float t = bottomRadius / radius;

    return -cosTheta * radius - radius * sqrt((cosTheta * cosTheta - 1.0f) + t * t);
}

float GetDistToCosmos(float cosTheta, float radius, float topRadius)
{
    float t = topRadius / radius;
    return -cosTheta * radius + radius * sqrt((cosTheta * cosTheta - 1.0f) + t * t);
}

// Must ensure input ray does not hit the earth
float GetDistToCosmos(in ScatteringParameters params, float h, float cosTheta)
{
    float bottomRadius = params.earthRadius;
    float radius = h + bottomRadius;
    float topRadius = params.topHeight + bottomRadius;
    return GetDistToCosmos(cosTheta, radius, topRadius);
}

float GetDistToSurface(in ScatteringParameters params, float3 p, float3 dir, float h, float cosTheta)
{
    return HitEarth(params, p, dir) ? GetDistToEarth(params, h, cosTheta) : GetDistToCosmos(params, h, cosTheta);
}

float TransformCosLatitudeToV(float cosTheta)
{
    float theta = acos(cosTheta) - HALF_PI;
    return 0.5 + 0.5 * sign(theta) * sqrt(abs(theta) * INV_HALF_PI);
}

float TransformVToCosLatitude(float v)
{
    float sg = v >= 0.5f ? 1.0f : -1.0f;
    float t = 2.0 * v - 1.0;
    return cos(t * t * HALF_PI * sg + HALF_PI);
}

float2 GetTransmittanceLutUV(in ScatteringParameters params, float h, float cosTheta)
{
    float bottomRadius = params.earthRadius;
    float radius = h + bottomRadius;
    float radius2 = radius * radius;
    float topRadius = params.topHeight + bottomRadius;
    float bottomRadius2 = bottomRadius * bottomRadius;
    float tangentLength = sqrt(radius2 - bottomRadius2);

    float d_min = topRadius - radius;
    float d_max = tangentLength + params.maxTangentLength;
    float d = GetDistToCosmos(cosTheta, radius, topRadius);

    float2 uv = float2((d - d_min) / (d_max - d_min), tangentLength / params.maxTangentLength);
    return uv;
}

float2 GetHeightAndCosZenith(in ScatteringParameters params, float2 uv)
{
    float bottomRadius = params.earthRadius;
    float tangentLength = uv.y * params.maxTangentLength;
    float bottomRadius2 = bottomRadius * bottomRadius;
    float radius = sqrt(bottomRadius2 + tangentLength * tangentLength);
    float radius2 = radius * radius;
    float topRadius = params.topHeight + bottomRadius;
    float topRadius2 = topRadius * topRadius;
    
    float d_min = topRadius - radius;
    float d_max = tangentLength + params.maxTangentLength;
    float d = uv.x * (d_max - d_min) + d_min;
    float cosTheta = -(d * d + radius2 - topRadius2) * rcp(max(2.0 * radius * d, 1e-3f));

    return float2(radius - bottomRadius, cosTheta);
}

float GetHeightFromUV(in ScatteringParameters params, float2 uv)
{
    float bottomRadius = params.earthRadius;
    float topRadius = params.topHeight + bottomRadius;
    float h = uv.y * (topRadius - bottomRadius);
    return h;
}

float GetCosZenithFromUV(in ScatteringParameters params, float h, float uv)
{
    float bottomRadius = params.earthRadius;
    float bottomRadius2 = bottomRadius * bottomRadius;
    float radius = h + bottomRadius;
    float radius2 = radius * radius;
    float tangentLength = sqrt(radius2 - bottomRadius2);
    float topRadius = params.topHeight + bottomRadius;
    float topRadius2 = topRadius * topRadius;
    
    float d_min = topRadius - radius;
    float d_max = tangentLength + params.maxTangentLength;
    float d = uv * (d_max - d_min) + d_min;
    float cosTheta = -(d * d + radius2 - topRadius2) * rcp(max(2.0 * radius * d, 1e-3f));

    return cosTheta;
}

#endif