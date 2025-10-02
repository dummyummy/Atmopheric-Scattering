Shader "Custom/AtmosphereSkybox"
{
    Properties { }
    SubShader
    {
        Tags
        {
            "RenderType" = "Background"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Background"
            "PreviewType" = "Skybox"
        }
        Pass
        {
            Name "AtmosphereSkybox"
            ZWrite Off
            ZTest LEqual
            
            HLSLPROGRAM
            #pragma enable_d3d11_debug_symbols
            
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
            #include "../Shaders/AtmosphericScatteringData.hlsl"

            struct appdata
            {
                float4 posOS : POSITION;
            };

            struct v2f
            {
                float4 posCS : SV_POSITION;
                float3 dirWS : TEXCOORD0;
            };

            TEXTURE2D(_PrecomputedAtmosphere);
            SAMPLER(atmosphere_sampler_linear_clamp);

            v2f vert(appdata i)
            {
                v2f o;
                o.posCS = TransformObjectToHClip(i.posOS.xyz);
                o.dirWS = TransformObjectToWorldDir(i.posOS.xyz);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                ScatteringParameters params = CollectParams();
                float3 p = GetScaledWorldPosition(_WorldSpaceCameraPos);
                float3 dirWS = normalize(i.dirWS);
                float3 right, forward;
                float3 up = normalize(p - params.earthCenter);
                GetLocalFrame(up, right, forward);
                float cosTheta = dot(up, dirWS);
                float2 uv;
                uv.x = GetLocalU(float2(dot(right, dirWS), dot(forward, dirWS)));
                uv.y = TransformCosLatitudeToV(cosTheta);
                float3 atmo = SAMPLE_TEXTURE2D(_PrecomputedAtmosphere, atmosphere_sampler_linear_clamp, uv).rgb;
                return float4(atmo, 1.0);
            }
            
            ENDHLSL
        }
    }
}
