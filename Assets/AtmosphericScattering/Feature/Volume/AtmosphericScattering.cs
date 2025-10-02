using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class AtmosphericScattering : VolumeComponent
{
    public MinFloatParameter topHeight = new MinFloatParameter(100.0f, 1.0f, true);
    public Vector3Parameter earthCenter = new Vector3Parameter(new Vector3(0.0f, -6378.0f, 0.0f), true);
    public ClampedFloatParameter mieG = new ClampedFloatParameter(0.8f, -0.999f, 0.999f, true);
    public MinFloatParameter atmosphereIntensity = new MinFloatParameter(10.0f, 0.0f, true);
    public MinFloatParameter atmosphereMultiScatteringIntensity = new MinFloatParameter(1.0f, 0.0f, true);
    public BoolParameter useFibonacciSampling = new BoolParameter(true, true);
}
