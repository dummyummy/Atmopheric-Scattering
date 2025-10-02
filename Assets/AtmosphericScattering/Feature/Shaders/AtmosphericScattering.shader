Shader "Custom/AtmosphericScattering"
{
    Properties { }
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        
        HLSLINCLUDE
            #pragma enable_d3d11_debug_symbols
        ENDHLSL
        
        Pass
        {
            Name "PrecomputeTransmittance"
            
            HLSLPROGRAM
            
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "AtmosphericScatteringData.hlsl"

            float4 frag(Varyings input) : SV_Target
            {
                ScatteringParameters params = CollectParams();
                float2 heightAndCosZenith = GetHeightAndCosZenith(params, input.texcoord);
                float3 src = params.earthCenter + float3(0, heightAndCosZenith.x + params.earthRadius, 0.0);
                float d = GetDistToCosmos(params, heightAndCosZenith.x, heightAndCosZenith.y);
                float3 dir = float3(sqrt(1.0 - heightAndCosZenith.y * heightAndCosZenith.y), heightAndCosZenith.y, 0.0);
                float3 dst = src + dir * d;
                float3 trans = Transmittance(params, src, dst);
                return float4(trans, 1.0);
            }

            ENDHLSL
        }

        Pass
        {
            Name "PrecomputeMultiScattering"
            
            HLSLPROGRAM
            
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "AtmosphericScatteringData.hlsl"

            #define N_DIRECTION 64
            #define N_STEP 20

            
            TEXTURE2D(_PrecomputedTransmittance);
            SAMPLER(transmittance_sampler_linear_clamp);
            float4 _SampleDirections[N_DIRECTION];

            float4 frag(Varyings input) : SV_Target
            {
                ScatteringParameters params = CollectParams();
                float height = GetHeightFromUV(params, input.texcoord);
                float cosSunTheta = 2.0 * input.texcoord.x - 1.0;
                float3 src = params.earthCenter + float3(0, height + params.earthRadius, 0.0);
                float3 lightDir = float3(sqrt(1.0 - cosSunTheta * cosSunTheta), cosSunTheta, 0.0);
                float3 G2 = 0.0;
                float3 Fms = 0.0;
                float invStep = 1.0 / N_STEP;
                float pu = INV_FOUR_PI; // uniform phase function
                
                for (int i = 0; i < N_DIRECTION; i++)
                {
                    float3 dir = _SampleDirections[i].xyz;
                    float dist = GetDistToSurface(params, src, dir, height, dir.y);
                    float3 dst = src + dir * dist;
                    float ds = dist * invStep;
                    float scatteringAngle = dot(lightDir, dir);
                    float3 g2 = 0.0;
                    float3 fms = 0.0;
                    
                    float3 depth = 0.0f;
                    
                    for (int s = 0; s < N_STEP; s++)
                    {
                        float3 p = lerp(src, dst, (s + 0.5) * invStep);
                        float h = GetHeight(params, p);
                        float cosTheta = dot(normalize(p - params.earthCenter), lightDir);
                        float3 scattering = RayleighScattering(params, h) + MieScattering(params, h);
                        float3 absorption = MieAbsorption(params, h) + OzoneAbsorption(params, h);
                        depth += (scattering + absorption) * ds;
                        float hitEarth = HitEarth(params, p, lightDir) ? 0.0 : 1.0;
                        float2 transUV = GetTransmittanceLutUV(params, h, cosTheta);
                        float3 trans2 = SAMPLE_TEXTURE2D(_PrecomputedTransmittance, transmittance_sampler_linear_clamp, transUV).rgb;
                        float3 trans1 = exp(-depth);
                        g2 += trans1 * Scattering(params, h, scatteringAngle) * trans2 * hitEarth * ds;
                        fms += trans1 * scattering * ds;
                    }
                    G2 += pu * g2 * _SampleDirections[i].w;
                    Fms += pu * fms * _SampleDirections[i].w;
                }

                float avg = rcp(float(N_DIRECTION));
                G2 *= avg;
                Fms *= avg;

                return float4(G2 * rcp(1.0 - Fms), 1.0);
            }

            ENDHLSL
        }

        Pass
        {
            Name "PrecomputeAtmosphere"
            
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "AtmosphericScatteringData.hlsl"
            
            TEXTURE2D(_PrecomputedTransmittance);
            SAMPLER(transmittance_sampler_linear_clamp);
            TEXTURE2D(_PrecomputedMultiScattering);
            SAMPLER(multiScattering_sampler_linear_clamp);

            float4 frag(Varyings input) : SV_Target
            {
                ScatteringParameters params = CollectParams();
                float3 cam = GetScaledWorldPosition(_WorldSpaceCameraPos);
                float h = GetHeight(params, cam);
                float cosTheta = TransformVToCosLatitude(input.texcoord.y);
                float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
                
                float3 right, forward;
                float3 up = normalize(cam - params.earthCenter);
                GetLocalFrame(up, right, forward);
                float3 src = cam;
                // float3 dir = float3(sqrt(1.0 - cosTheta * cosTheta), cosTheta, 0.0);
                float2 xy = normalize(GetLocalXY(input.texcoord.x)) * sinTheta;
                float3 dir = normalize(xy.x * right + xy.y * forward + cosTheta * up);
                
                float dist = GetDistToSurface(params, src, dir, h, cosTheta);
                float3 dst = src + dir * dist;
                float3 atmo = 0.0f;
                float3 depth = 0.0f;
                float invStep = rcp(MAX_STEPS);
                float ds = dist * invStep;

                Light light = GetMainLight();
                float3 lightDir = light.direction;
                float scatteringAngle = dot(lightDir, dir);

                for (float i = 0.0; i < MAX_STEPS; i += 1.0)
                {
                    float3 p = lerp(src, dst, (i + 0.5) * invStep);
                    h = GetHeight(params, p);
                    cosTheta = dot(normalize(p - params.earthCenter), lightDir);
                    float3 scattering = RayleighScattering(params, h) + MieScattering(params, h);
                    float3 absorption = MieAbsorption(params, h) + OzoneAbsorption(params, h);
                    depth += (scattering + absorption) * ds;
                    float hitEarth = HitEarth(params, p, lightDir) ? 0.0 : 1.0;
                    float2 transUV = GetTransmittanceLutUV(params, h, cosTheta);
                    float3 trans2 = SAMPLE_TEXTURE2D(_PrecomputedTransmittance, transmittance_sampler_linear_clamp, transUV).rgb;
                    float3 trans1 = exp(-depth);
                    atmo += trans1 * Scattering(params, h, scatteringAngle) * trans2 * hitEarth * ds;
                    transUV.x = 0.5 + 0.5 * cosTheta;
                    transUV.y = h / params.topHeight;
                    float3 multiScattering = SAMPLE_TEXTURE2D(_PrecomputedMultiScattering, multiScattering_sampler_linear_clamp, transUV).rgb;
                    atmo += trans1 * scattering * multiScattering * ds * params.atmosphereMultiScatteringIntensity;
                }

                atmo *= light.color * params.atmosphereIntensity;

                return float4(atmo, 1.0);
            }
            
            ENDHLSL
        }

        Pass
        {
            ZTest Always
            ZWrite Off
            
            Name "AerialPerspective"
            
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "AtmosphericScatteringData.hlsl"
            
            TEXTURE2D_ARRAY(_PrecomputedAerialPerspective);
            SAMPLER(aerial_sample_linear_clamp);
            float4 _AerialPerspectiveParams; // size.xy, n_slice

            float4 frag(Varyings input) : SV_Target
            {
                float depth = SampleSceneDepth(input.texcoord);
                float3 color = SampleSceneColor(input.texcoord);
                if (depth != UNITY_RAW_FAR_CLIP_VALUE)
                {
                    float near = _ProjectionParams.y;
                    float far = _ProjectionParams.z;
                    float linear_depth = LinearEyeDepth(depth, _ZBufferParams);
                    float t = (linear_depth - near) * _AerialPerspectiveParams.z / (far - near);
                    float slice = floor(t - 0.5);
                    float w = saturate(frac(t - 0.5));
                    float4 aerial1 = slice < 0 ? float4(0.0, 0.0, 0.0, 1.0) : SAMPLE_TEXTURE2D_ARRAY_LOD(_PrecomputedAerialPerspective, aerial_sample_linear_clamp, input.texcoord, slice, 0);
                    float4 aerial2 = SAMPLE_TEXTURE2D_ARRAY_LOD(_PrecomputedAerialPerspective, aerial_sample_linear_clamp, input.texcoord, slice + 1, 0);
                    float4 aerial = lerp(aerial1, aerial2, w);
                    color = color * aerial.w + aerial.rgb;
                    // color = w;
                    // color = (slice + 1.0) / _AerialPerspectiveParams.z;
                }
                return float4(color, 1.0);
            }
            
            ENDHLSL
        }
    }
}
