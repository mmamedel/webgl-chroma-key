# Ultra Key WebGPU - Implementation Details

## Detailed Algorithm Specifications

### 1. Improved Matte Generation Function

```glsl
float generateMatte(vec3 color, vec3 keyColor, MatteGenParams params) {
    // Convert to HSV
    vec3 hsv = rgb2hsv(color);
    vec3 targetHSV = rgb2hsv(keyColor);

    // Calculate luminance for highlight/shadow handling
    float luma = dot(color, vec3(0.299, 0.587, 0.114));

    // Tolerance affects weight multiplication
    float tolFactor = 1.0 + (params.tolerance - 50.0) * 0.02;
    vec3 weights = vec3(4.0, 1.0, 2.0) * tolFactor;

    // Weighted distance in HSV space
    vec3 diff = targetHSV - hsv;

    // Handle hue wraparound (hue is circular 0-1)
    if (abs(diff.x) > 0.5) {
        diff.x = diff.x - sign(diff.x);
    }

    float dist = length(weights * diff);

    // Transparency affects threshold and slope
    float threshold = 0.5 + (params.transparency - 50.0) * 0.01;
    float slope = 3.0 + (params.transparency - 50.0) * 0.05;

    // Base alpha from distance
    float alpha = 1.0 - smoothstep(0.0, threshold, dist * slope);

    // Highlight adjustment (for bright background areas)
    if (luma > 0.6) {
        float highlightMask = smoothstep(0.6, 0.9, luma);
        float highlightAdjust = 1.0 + (params.highlight - 10.0) * 0.02;
        // Increase transparency in bright areas
        alpha = mix(alpha, alpha * highlightAdjust, highlightMask);
    }

    // Shadow adjustment (for dark background areas)
    if (luma < 0.4) {
        float shadowMask = smoothstep(0.4, 0.0, luma);
        float shadowAdjust = 1.0 + (params.shadow - 50.0) * 0.02;
        // Adjust transparency in dark areas
        alpha = mix(alpha, alpha * shadowAdjust, shadowMask);
    }

    // Pedestal: shift entire alpha range
    if (params.pedestal > 10.0) {
        float pedestalShift = (params.pedestal - 10.0) * 0.01;
        alpha = saturate(alpha - pedestalShift);
    }

    return saturate(alpha);
}
```

### 2. Spill Suppression Algorithm

```glsl
vec3 suppressSpill(vec3 color, float alpha, vec3 keyColor, SpillParams params) {
    // Only process visible pixels
    if (alpha < 0.05) return color;

    vec3 hsv = rgb2hsv(color);
    vec3 keyHSV = rgb2hsv(keyColor);

    // Calculate spill amount based on hue proximity
    float hueDist = abs(hsv.x - keyHSV.x);
    // Handle hue wraparound
    if (hueDist > 0.5) hueDist = 1.0 - hueDist;

    // Range parameter controls how wide the affected hue range is
    float rangeThreshold = params.range * 0.005; // 0-0.5 range in hue space
    float spillDetection = smoothstep(rangeThreshold, 0.0, hueDist);

    // Also consider saturation - more saturated = more spill
    spillDetection *= hsv.y;

    // Overall spillage amount
    float spillAmount = spillDetection * params.spillage * 0.01;

    if (spillAmount > 0.01) {
        // Get complementary color
        vec3 complementaryHSV = keyHSV;
        complementaryHSV.x = fract(complementaryHSV.x + 0.5); // Opposite on color wheel
        vec3 complementary = hsv2rgb(complementaryHSV);

        // Shift hue toward complementary
        // This cancels out the key color (green → magenta, blue → orange)
        float hueShiftAmount = spillAmount * 0.5;
        color = mix(color, complementary, hueShiftAmount);

        // Desaturate spill-affected areas
        float desatAmount = spillAmount * params.desaturate * 0.01;
        float luma = dot(color, vec3(0.299, 0.587, 0.114));
        color = mix(color, vec3(luma), desatAmount);

        // Luma compensation (prevent darkening from desaturation)
        float lumaCompensation = 1.0 + (params.luma - 50.0) * spillAmount * 0.02;
        color *= lumaCompensation;
    }

    return saturate(color);
}
```

### 3. HSV to RGB Conversion (needed for spill)

```glsl
vec3 hsv2rgb(vec3 hsv) {
    vec3 rgb = vec3(0.0);
    float h = hsv.x * 6.0;
    float s = hsv.y;
    float v = hsv.z;

    float c = v * s;
    float x = c * (1.0 - abs(mod(h, 2.0) - 1.0));
    float m = v - c;

    if (h < 1.0) {
        rgb = vec3(c, x, 0.0);
    } else if (h < 2.0) {
        rgb = vec3(x, c, 0.0);
    } else if (h < 3.0) {
        rgb = vec3(0.0, c, x);
    } else if (h < 4.0) {
        rgb = vec3(0.0, x, c);
    } else if (h < 5.0) {
        rgb = vec3(x, 0.0, c);
    } else {
        rgb = vec3(c, 0.0, x);
    }

    return rgb + m;
}
```

### 4. Output Mode Selection

```glsl
vec4 selectOutputMode(vec3 color, float alpha, vec3 background, int mode) {
    if (mode == 0) {
        // Composite mode
        vec3 composite = mix(background, color, alpha);
        return vec4(composite, 1.0);
    }
    else if (mode == 1) {
        // Alpha Channel mode (grayscale)
        return vec4(vec3(alpha), 1.0);
    }
    else if (mode == 2) {
        // Status mode (diagnostic color-coding)
        vec3 statusColor;
        if (alpha > 0.95) {
            statusColor = vec3(1.0); // White: fully opaque (GOOD)
        } else if (alpha < 0.05) {
            statusColor = vec3(0.0); // Black: fully transparent (GOOD)
        } else if (alpha > 0.7) {
            statusColor = vec3(0.3, 0.5, 1.0); // Blue: acceptable
        } else if (alpha > 0.4) {
            statusColor = vec3(1.0, 1.0, 0.0); // Yellow: marginal
        } else {
            statusColor = vec3(1.0, 0.0, 0.0); // Red: poor quality
        }
        return vec4(statusColor, 1.0);
    }
    else if (mode == 3) {
        // Color Matte mode (colored overlay on semi-transparent areas)
        vec3 overlay = color;
        if (alpha > 0.1 && alpha < 0.9) {
            // Highlight problem areas in magenta
            overlay = mix(overlay, vec3(1.0, 0.0, 1.0), 0.5);
        }
        return vec4(overlay, 1.0);
    }

    // Default: composite
    return vec4(mix(background, color, alpha), 1.0);
}
```

### 5. Color Correction

```glsl
vec3 colorCorrect(vec3 color, float alpha, ColorCorrectionParams params) {
    // Only correct visible pixels
    if (alpha < 0.05) return color;

    // Saturation adjustment (0-200, 100=normal)
    if (abs(params.saturation - 100.0) > 1.0) {
        float satFactor = params.saturation * 0.01;
        float luma = dot(color, vec3(0.299, 0.587, 0.114));
        color = mix(vec3(luma), color, satFactor);
    }

    // Hue shift (-180 to +180 degrees)
    if (abs(params.hue) > 1.0) {
        vec3 hsv = rgb2hsv(color);
        hsv.x = fract(hsv.x + params.hue / 360.0);
        color = hsv2rgb(hsv);
    }

    // Luminance adjustment (0-200, 100=normal)
    if (abs(params.luminance - 100.0) > 1.0) {
        float lumFactor = params.luminance * 0.01;
        color *= lumFactor;
    }

    return saturate(color);
}
```

---

## Matte Cleanup Implementation (Multi-Pass)

### Pass 1: Choke (Erosion/Dilation)

```glsl
// Compute shader for parallel processing
@compute @workgroup_size(8, 8)
fn choke_matte(
    @builtin(global_invocation_id) id: vec3<u32>,
    @group(0) @binding(0) alpha_in: texture_2d<f32>,
    @group(0) @binding(1) alpha_out: texture_storage_2d<rgba8unorm, write>,
    @group(0) @binding(2) params: Uniforms
) {
    let coord = vec2<i32>(id.xy);
    let size = textureDimensions(alpha_in);

    if (coord.x >= size.x || coord.y >= size.y) {
        return;
    }

    let alpha = textureLoad(alpha_in, coord, 0).r;
    var result = alpha;

    // Choke parameter: positive = erode (shrink), negative = dilate (grow)
    if (abs(params.choke) > 1.0) {
        let radius = i32(abs(params.choke) * 0.1); // Max ~10 pixel radius
        var minAlpha = 1.0;
        var maxAlpha = 0.0;

        // Sample neighborhood
        for (var dy = -radius; dy <= radius; dy = dy + 1) {
            for (var dx = -radius; dx <= radius; dx = dx + 1) {
                let offset = coord + vec2<i32>(dx, dy);
                if (offset.x >= 0 && offset.x < size.x &&
                    offset.y >= 0 && offset.y < size.y) {
                    let sample = textureLoad(alpha_in, offset, 0).r;
                    minAlpha = min(minAlpha, sample);
                    maxAlpha = max(maxAlpha, sample);
                }
            }
        }

        // Positive choke = erosion (use minimum)
        // Negative choke = dilation (use maximum)
        if (params.choke > 0.0) {
            result = minAlpha;
        } else {
            result = maxAlpha;
        }
    }

    textureStore(alpha_out, coord, vec4<f32>(result, result, result, 1.0));
}
```

### Pass 2: Soften (Edge-Aware Blur)

```glsl
@compute @workgroup_size(8, 8)
fn soften_matte(
    @builtin(global_invocation_id) id: vec3<u32>,
    @group(0) @binding(0) alpha_in: texture_2d<f32>,
    @group(0) @binding(1) alpha_out: texture_storage_2d<rgba8unorm, write>,
    @group(0) @binding(2) params: Uniforms
) {
    let coord = vec2<i32>(id.xy);
    let size = textureDimensions(alpha_in);

    if (coord.x >= size.x || coord.y >= size.y) {
        return;
    }

    let alpha = textureLoad(alpha_in, coord, 0).r;
    var result = alpha;

    if (params.soften > 1.0) {
        // Detect if we're on an edge
        let dx = textureLoad(alpha_in, coord + vec2<i32>(1, 0), 0).r -
                 textureLoad(alpha_in, coord - vec2<i32>(1, 0), 0).r;
        let dy = textureLoad(alpha_in, coord + vec2<i32>(0, 1), 0).r -
                 textureLoad(alpha_in, coord - vec2<i32>(0, 1), 0).r;
        let edgeStrength = length(vec2<f32>(dx, dy));

        // Only blur edges, not interior or exterior
        if (edgeStrength > 0.1) {
            let radius = i32(params.soften * 0.1); // Max ~10 pixel radius
            var sum = 0.0;
            var weight = 0.0;

            // Gaussian-like blur
            for (var dy = -radius; dy <= radius; dy = dy + 1) {
                for (var dx = -radius; dx <= radius; dx = dx + 1) {
                    let offset = coord + vec2<i32>(dx, dy);
                    if (offset.x >= 0 && offset.x < size.x &&
                        offset.y >= 0 && offset.y < size.y) {
                        let dist = length(vec2<f32>(f32(dx), f32(dy)));
                        let w = exp(-dist * dist / (f32(radius) * f32(radius)));
                        sum += textureLoad(alpha_in, offset, 0).r * w;
                        weight += w;
                    }
                }
            }

            result = sum / weight;
        }
    }

    textureStore(alpha_out, coord, vec4<f32>(result, result, result, 1.0));
}
```

### Pass 3: Contrast & Mid Point

```glsl
float applyContrast(float alpha, float contrast, float midPoint) {
    if (contrast < 1.0) return alpha;

    // Normalize midPoint to 0-1 range
    float pivot = midPoint * 0.01;

    // Apply contrast curve around pivot point
    float contrastAmount = contrast * 0.01;

    // Map alpha through S-curve
    float adjusted;
    if (alpha < pivot) {
        // Below pivot: compress toward black
        float t = alpha / pivot;
        adjusted = pivot * pow(t, 1.0 + contrastAmount);
    } else {
        // Above pivot: compress toward white
        float t = (alpha - pivot) / (1.0 - pivot);
        adjusted = pivot + (1.0 - pivot) * pow(t, 1.0 / (1.0 + contrastAmount));
    }

    return saturate(adjusted);
}
```

---

## WebGPU Pipeline Setup

### Complete Uniform Structure

```rust
#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct UltraKeyUniforms {
    // System (16 bytes)
    key_color: [f32; 3],
    output_mode: u32,

    // Matte Generation (32 bytes)
    transparency: f32,
    highlight: f32,
    shadow: f32,
    tolerance: f32,

    pedestal: f32,
    _padding1: [f32; 3],

    // Matte Cleanup (16 bytes)
    choke: f32,
    soften: f32,
    contrast: f32,
    mid_point: f32,

    // Spill Suppression (16 bytes)
    desaturate: f32,
    range: f32,
    spillage: f32,
    luma: f32,

    // Color Correction (16 bytes)
    saturation: f32,
    hue: f32,
    luminance: f32,
    _padding2: f32,
}

impl Default for UltraKeyUniforms {
    fn default() -> Self {
        Self {
            key_color: [0.157, 0.576, 0.129], // Default green
            output_mode: 0, // Composite

            transparency: 50.0,
            highlight: 10.0,
            shadow: 50.0,
            tolerance: 50.0,
            pedestal: 10.0,
            _padding1: [0.0; 3],

            choke: 0.0,
            soften: 0.0,
            contrast: 0.0,
            mid_point: 50.0,

            desaturate: 50.0,
            range: 50.0,
            spillage: 50.0,
            luma: 50.0,

            saturation: 100.0,
            hue: 0.0,
            luminance: 100.0,
            _padding2: 0.0,
        }
    }
}

impl UltraKeyUniforms {
    fn aggressive_preset() -> Self {
        Self {
            transparency: 70.0,
            tolerance: 60.0,
            ..Self::default()
        }
    }
}
```

### Render Pipeline

```rust
// Main keying pass
let keying_pipeline = device.create_render_pipeline(&RenderPipelineDescriptor {
    label: Some("Ultra Key Pipeline"),
    layout: Some(&pipeline_layout),
    vertex: VertexState {
        module: &shader_module,
        entry_point: "vs_main",
        buffers: &[vertex_buffer_layout],
    },
    fragment: Some(FragmentState {
        module: &shader_module,
        entry_point: "fs_main",
        targets: &[Some(ColorTargetState {
            format: TextureFormat::Rgba8Unorm,
            blend: None,
            write_mask: ColorWrites::ALL,
        })],
    }),
    primitive: PrimitiveState::default(),
    depth_stencil: None,
    multisample: MultisampleState::default(),
    multiview: None,
});

// Compute pipeline for matte cleanup
let cleanup_pipeline = device.create_compute_pipeline(&ComputePipelineDescriptor {
    label: Some("Matte Cleanup Pipeline"),
    layout: Some(&compute_layout),
    module: &compute_shader_module,
    entry_point: "choke_and_soften",
});
```

---

## Performance Optimization Tips

### 1. Early Exit for Far-from-Key Pixels

```glsl
// Quick rejection test before expensive operations
float quickDist = length(color - keyColor);
if (quickDist > 0.5) {
    // Definitely not key color, skip expensive HSV conversion
    return 1.0; // Fully opaque
}
```

### 2. Conditional Execution

```glsl
// Only run cleanup if parameters are non-default
if (params.choke != 0.0 || params.soften != 0.0) {
    alpha = cleanupMatte(alpha, uv, params);
}

// Only run spill suppression if enabled
if (params.spillage > 5.0) {
    color = suppressSpill(color, alpha, keyColor, params);
}
```

### 3. LOD System

```glsl
uniform int quality_level; // 0=preview, 1=high, 2=final

float soften_radius = params.soften * quality_multipliers[quality_level];
```

### 4. Compute Shader for Large Kernel Operations

Use compute shaders for:

- Choke (erosion/dilation) - requires neighborhood sampling
- Soften (blur) - requires many texture reads
- Any operation that reads > 9 samples

Benefits:

- Shared memory for neighborhood caching
- Better cache coherency
- Parallel execution

---

## Testing Checklist

### Algorithm Validation

- [ ] Key color selection produces clean matte
- [ ] Transparency adjusts alpha threshold correctly
- [ ] Tolerance expands/contracts color range
- [ ] Highlight handles bright background areas
- [ ] Shadow handles dark background areas
- [ ] Pedestal shifts alpha properly

### Output Modes

- [ ] Alpha Channel shows grayscale matte
- [ ] Status mode color-codes quality correctly
- [ ] Composite blends properly with background

### Spill Suppression

- [ ] Detects green/blue cast on subject
- [ ] Hue shifts toward complementary color
- [ ] Range parameter limits affected colors
- [ ] Desaturate removes color appropriately
- [ ] Luma compensates for darkening

### Edge Cases

- [ ] Dark clothing vs. dark shadows
- [ ] Bright clothing vs. bright spots
- [ ] Hair and fine detail preservation
- [ ] Motion blur handling
- [ ] Reflective surfaces

### Performance

- [ ] 60 FPS @ 1080p (16ms frame time)
- [ ] No visible lag when adjusting parameters
- [ ] Multi-pass overhead acceptable

---

## Common Implementation Pitfalls

1. **Hue Wraparound:** Remember hue is circular (0-1 wraps to 0)
2. **Color Space Confusion:** Keep track of RGB vs HSV
3. **Alpha Premultiplication:** Ensure proper alpha handling in blend
4. **Uniform Alignment:** WebGPU requires 16-byte alignment
5. **Texture Format:** Use appropriate format for alpha (RGBA8 or RGBA16)
6. **Coordinate Systems:** Ensure UV coords match between passes
