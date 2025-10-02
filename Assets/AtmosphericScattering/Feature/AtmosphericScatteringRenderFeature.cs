using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AtmosphericScatteringRenderFeature : ScriptableRendererFeature
{
    [Serializable]
    public class AtmosphericScatteringParams
    {
        #region
        public float topHeight = 85; // in km
        public float earthRadius = 6378;
        public Vector3 earthCenter = new Vector3(0.0f, -6378.0f, 0.0f);
        #endregion
        
        #region Rayleigh
        public Vector3 rayleighScatteringCoefficient = new Vector3(5.802f, 13.558f, 33.1f) * 1e-3f;
        public float rayleighHeight = 8.5f;
        #endregion
        
        #region Mie
        public Vector3 mieScatteringCoefficient = Vector3.one * 3.996f * 1e-3f;
        public Vector3 mieAbsorptionCoefficient = Vector3.one * 4.40f * 1e-3f;
        public float mieHeight = 1.2f;
        [Range(0, 1)] public float mieG = 0.8f;
        #endregion
        
        #region Ozone
        public Vector3 ozoneAbsorptionCoefficient = new Vector3(0.65f, 1.881f, 0.085f) * 1e-3f;
        public float ozoneCenter = 25;
        public float ozoneWidth = 15;
        #endregion

        #region Intermediate
        public float maxTangentLength = -1.0f;
        #endregion

        public int maxSteps = 128;
        public float atmosphereIntensity = 10.0f;
        public float atmosphereMultiScatteringIntensity = 1.0f;

        public void Init()
        {
            var volume = VolumeManager.instance.stack.GetComponent<AtmosphericScattering>();

            if (volume)
            {
                topHeight = volume.topHeight.value;
                earthCenter = volume.earthCenter.value;
                mieG = volume.mieG.value;
                atmosphereIntensity = volume.atmosphereIntensity.value;
                atmosphereMultiScatteringIntensity = volume.atmosphereMultiScatteringIntensity.value;
            }
            
            float topRadius = earthRadius + topHeight;
            maxTangentLength = Mathf.Sqrt(topRadius * topRadius - earthRadius * earthRadius);
        }

        public void PrepareUniforms(CommandBuffer cmd)
        {
            cmd.SetGlobalFloat("topHeight", topHeight);
            cmd.SetGlobalFloat("earthRadius", earthRadius);
            cmd.SetGlobalVector("earthCenter", earthCenter);
            cmd.SetGlobalVector("rayleighScatteringCoefficient", rayleighScatteringCoefficient);
            cmd.SetGlobalFloat("rayleighHeight", rayleighHeight);
            cmd.SetGlobalVector("mieScatteringCoefficient", mieScatteringCoefficient);
            cmd.SetGlobalVector("mieAbsorptionCoefficient", mieAbsorptionCoefficient);
            cmd.SetGlobalFloat("mieHeight", mieHeight);
            cmd.SetGlobalFloat("mieG", mieG);
            cmd.SetGlobalVector("ozoneAbsorptionCoefficient", ozoneAbsorptionCoefficient);
            cmd.SetGlobalFloat("ozoneCenter", ozoneCenter);
            cmd.SetGlobalFloat("ozoneWidth", ozoneWidth);
            cmd.SetGlobalFloat("maxTangentLength", maxTangentLength);
            cmd.SetGlobalFloat("atmosphereIntensity", atmosphereIntensity);
            cmd.SetGlobalFloat("atmosphereMultiScatteringIntensity", atmosphereMultiScatteringIntensity);
        }
    }
    
    class TransmittancePass : ScriptableRenderPass
    {
        private Material m_Material;
        private RTHandle m_RTHandle;
        private AtmosphericScatteringParams m_Params;
        
        public TransmittancePass(Material material)
        {
            m_Material = material;
        }
        
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            ConfigureTarget(m_RTHandle);
        }

        public void Setup(AtmosphericScatteringParams p, RTHandle handle)
        {
            m_Params = p;
            m_RTHandle = handle;
        }

        public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get("AtmosphericScatteringTransmittancePass");
            m_Params.PrepareUniforms(cmd);
            Blitter.BlitTexture(cmd, BuiltinRenderTextureType.None, new Vector4(1.0f, 1.0f, 0.0f, 0.0f), m_Material, 0);
            cmd.SetGlobalTexture("_PrecomputedTransmittance", m_RTHandle);
            ctx.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
            
        }
    }
    
    class MultiScatteringPass : ScriptableRenderPass
    {
        private Material m_Material;
        private RTHandle m_RTHandle;
        private AtmosphericScatteringParams m_Params;

        public Vector4[] sampleDirections;
        
        public MultiScatteringPass(Material material)
        {
            m_Material = material;
            
            sampleDirections = new Vector4[64];
        }
        
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            ConfigureTarget(m_RTHandle);
        }

        public void Setup(AtmosphericScatteringParams p, RTHandle handle, bool useFibonacciSampling)
        {
            m_Params = p;
            m_RTHandle = handle;

            float TWO_PI = 2.0f * Mathf.PI;
            if (useFibonacciSampling)
            {
                float PHI = (Mathf.Sqrt(5.0f) - 1) / 2.0f;
                for (int n = 1; n <= 64; n++)
                {
                    float y = (2.0f * n - 1) / 64 - 1;
                    float t = Mathf.Sqrt(1 - y * y);
                    float x = Mathf.Cos(TWO_PI * n * PHI) * t;
                    float z = Mathf.Sin(TWO_PI * n * PHI) * t;
                    sampleDirections[n - 1] = new Vector4(x, y, z, 2.0f * TWO_PI);
                }
            }
            else
            {
                for (int phi = 0; phi < 8; phi++)
                {
                    for (int theta = 0; theta < 8; theta++)
                    {
                        int index = phi * 8 + theta;
                        float u = (theta + 0.5f) / 8.0f;
                        float v = (phi + 0.5f) / 8.0f;
                        float x = Mathf.Cos(u * TWO_PI) * Mathf.Sin(v * Mathf.PI);
                        float y = Mathf.Cos(v * Mathf.PI);
                        float z = Mathf.Sin(u * TWO_PI) * Mathf.Sin(v * Mathf.PI);
                        sampleDirections[index] = new Vector4(x, y, z, 2.0f * TWO_PI);
                    }
                }
            }
        }

        public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get("AtmosphericScatteringMultiScatteringPass");
            m_Params.PrepareUniforms(cmd);
            cmd.SetGlobalVectorArray("_SampleDirections", sampleDirections);
            Blitter.BlitTexture(cmd, BuiltinRenderTextureType.None, new Vector4(1.0f, 1.0f, 0.0f, 0.0f), m_Material, 1);
            cmd.SetGlobalTexture("_PrecomputedMultiScattering", m_RTHandle);
            ctx.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
        }
    }


    // Skyview LUT Pass
    class AtmospherePass : ScriptableRenderPass
    {
        private Material m_Material;
        private RTHandle m_RTHandle;
        private AtmosphericScatteringParams m_Params;
        
        public AtmospherePass(Material material)
        {
            m_Material = material;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            ConfigureTarget(m_RTHandle);
        }

        public void Setup(AtmosphericScatteringParams p, RTHandle handle)
        {
            m_Params = p;
            m_RTHandle = handle;
        }

        public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get("AtmosphericScatteringAtmospherePass");
            m_Params.PrepareUniforms(cmd);
            Blitter.BlitTexture(cmd, BuiltinRenderTextureType.None, new Vector4(1.0f, 1.0f, 0.0f, 0.0f), m_Material, 2);
            cmd.SetGlobalTexture("_PrecomputedAtmosphere", m_RTHandle);
            ctx.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
        }
    }

    class AerialPerspectivePass : ScriptableRenderPass
    {
        private ComputeShader m_ComputeShader;
        private RTHandle m_RTHandle;
        private int kernel;
        private AtmosphericScatteringParams m_Params;

        public AerialPerspectivePass(ComputeShader shader)
        {
            m_ComputeShader = shader;
            kernel = m_ComputeShader.FindKernel("AerialPerspective");
        }

        public void Setup(AtmosphericScatteringParams p, RTHandle handle)
        {
            m_Params = p;
            m_RTHandle = handle;
        }

        public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get("AtmosphericScatteringAerialPerspectivePass");
            m_Params.PrepareUniforms(cmd);
            cmd.SetGlobalVector("_AerialPerspectiveParams", new Vector4(32, 32, 24, 0));
            cmd.SetComputeTextureParam(m_ComputeShader, kernel, "_PrecomputedAerialPerspective", m_RTHandle);
            cmd.SetGlobalTexture("_PrecomputedAerialPerspective", m_RTHandle);
            cmd.DispatchCompute(m_ComputeShader, kernel, 4, 4, 1);
            ctx.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
        }
    }
    
    class AtmosphereFog : ScriptableRenderPass
    {
        private Material m_Material;
        private RTHandle m_RTHandle;
        private AtmosphericScatteringParams m_Params;
        
        public AtmosphereFog(Material material)
        {
            m_Material = material;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            ConfigureTarget(m_RTHandle);
        }

        public void Setup(AtmosphericScatteringParams p, RTHandle handle)
        {
            m_Params = p;
            m_RTHandle = handle;
        }

        public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get("AtmosphericScatteringAtmosphereFogPass");
            m_Params.PrepareUniforms(cmd);
            Blitter.BlitTexture(cmd, BuiltinRenderTextureType.None, new Vector4(1.0f, 1.0f, 0.0f, 0.0f), m_Material, 3);
            ctx.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
        }
    }

    public Shader m_Shader; // Atmosphere shader
    public ComputeShader m_ComputeShader;
    // public Shader m_SkyboxShader;

    private Material m_Material;
    // private Material m_SkyboxMaterial;
    private Material originalSkyboxMaterial;
    private AtmosphericScatteringParams m_Params;
    
    TransmittancePass m_TransmittancePass;
    MultiScatteringPass m_MultiScatteringPass;
    AtmospherePass m_AtmopsherePass;
    AerialPerspectivePass m_AerialPerspectivePass;
    AtmosphereFog m_AtmosphereFogPass;

    private RTHandle m_TransmittanceLUT;
    private RTHandle m_AtmopshereLUT;
    private RTHandle m_MultiScatteringLUT;
    private RTHandle m_AerialPerspectiveLUT;

    /// <inheritdoc/>
    public override void Create()
    {
        if (m_Shader)
        {
            m_Material = CoreUtils.CreateEngineMaterial(m_Shader);
        }
        m_Params ??= new AtmosphericScatteringParams();

        if (m_Material)
        {
            m_TransmittancePass ??= new TransmittancePass(m_Material)
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingOpaques
            };
        
            m_MultiScatteringPass ??= new MultiScatteringPass(m_Material)
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingOpaques
            };
        
            m_AtmopsherePass ??= new AtmospherePass(m_Material)
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingOpaques
            };
            
            m_AtmosphereFogPass ??= new AtmosphereFog(m_Material)
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing
            };
        }

        if (m_ComputeShader)
        {
            m_AerialPerspectivePass ??= new AerialPerspectivePass(m_ComputeShader)
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingOpaques
            };
        }
    }
    
    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        if (m_Params == null)
        {
            m_Params = new AtmosphericScatteringParams();
        }
        m_Params.Init();
        var volume = VolumeManager.instance.stack.GetComponent<AtmosphericScattering>();
        
        RenderTextureDescriptor desc = new RenderTextureDescriptor(256, 64)
        {
            colorFormat = RenderTextureFormat.ARGBHalf,
            dimension = TextureDimension.Tex2D,
            depthStencilFormat = GraphicsFormat.None,
            depthBufferBits = 0,
            autoGenerateMips = false
        };
        RenderingUtils.ReAllocateIfNeeded(ref m_TransmittanceLUT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp);
        m_TransmittancePass?.Setup(m_Params, m_TransmittanceLUT);

        desc.width = 32;
        desc.height = 32;
        RenderingUtils.ReAllocateIfNeeded(ref m_MultiScatteringLUT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp);
        m_MultiScatteringPass?.Setup(m_Params, m_MultiScatteringLUT, volume.useFibonacciSampling.value);
        
        desc.width = 256;
        desc.height = 128;
        RenderingUtils.ReAllocateIfNeeded(ref m_AtmopshereLUT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp);
        m_AtmopsherePass?.Setup(m_Params, m_AtmopshereLUT);

        desc.width = 32;
        desc.height = 32;
        desc.dimension = TextureDimension.Tex2DArray;
        desc.volumeDepth = 24;
        desc.enableRandomWrite = true;
        RenderingUtils.ReAllocateIfNeeded(ref m_AerialPerspectiveLUT, desc, FilterMode.Bilinear, TextureWrapMode.Clamp);
        m_AerialPerspectivePass?.Setup(m_Params, m_AerialPerspectiveLUT);
        
        m_AtmosphereFogPass?.Setup(m_Params, renderingData.cameraData.renderer.cameraColorTargetHandle);
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (m_TransmittancePass != null)
        {
            renderer.EnqueuePass(m_TransmittancePass);
        }
        if (m_MultiScatteringPass != null)
        {
            renderer.EnqueuePass(m_MultiScatteringPass);
        }
        if (m_AtmopsherePass != null)
        {
            renderer.EnqueuePass(m_AtmopsherePass);
        }
        if (m_AerialPerspectivePass != null)
        {
            renderer.EnqueuePass(m_AerialPerspectivePass);
        }
        if (m_AtmosphereFogPass != null)
        {
            m_AtmosphereFogPass.ConfigureInput(ScriptableRenderPassInput.Color);
            m_AtmosphereFogPass.ConfigureInput(ScriptableRenderPassInput.Depth);
            renderer.EnqueuePass(m_AtmosphereFogPass);
        }
    }

    protected override void Dispose(bool disposing)
    {
        m_TransmittancePass?.Dispose();
        m_MultiScatteringPass?.Dispose();
        m_AtmopsherePass?.Dispose();
        m_AerialPerspectivePass?.Dispose();
        m_AtmosphereFogPass?.Dispose();
        
        m_TransmittanceLUT?.Release();
        m_MultiScatteringLUT?.Release();
        m_AtmopshereLUT?.Release();
        m_AerialPerspectiveLUT?.Release();

        if (m_Material)
        {
            CoreUtils.Destroy(m_Material);
        }
    }
}