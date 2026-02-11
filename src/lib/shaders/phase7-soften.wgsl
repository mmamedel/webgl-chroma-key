// Phase 7: Soften (Blur) Shader
// Pass 3: Applies blur to the alpha channel

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) texCoord: vec2f,
};

struct SoftenUniforms {
    resolution: vec2f,
    soften: f32,
    _padding: f32,
};

@group(0) @binding(0) var textureSampler: sampler;
@group(0) @binding(1) var inputTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: SoftenUniforms;

@vertex
fn vs(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
    let positions = array<vec2f, 6>(
        vec2f(-1.0, -1.0),
        vec2f( 1.0, -1.0),
        vec2f(-1.0,  1.0),
        vec2f(-1.0,  1.0),
        vec2f( 1.0, -1.0),
        vec2f( 1.0,  1.0),
    );
    
    let texCoords = array<vec2f, 6>(
        vec2f(0.0, 0.0),
        vec2f(1.0, 0.0),
        vec2f(0.0, 1.0),
        vec2f(0.0, 1.0),
        vec2f(1.0, 0.0),
        vec2f(1.0, 1.0),
    );
    
    var output: VertexOutput;
    output.position = vec4f(positions[vertexIndex], 0.0, 1.0);
    output.texCoord = texCoords[vertexIndex];
    return output;
}

@fragment
fn fs(input: VertexOutput) -> @location(0) vec4f {
    let pixelSize = 1.0 / uniforms.resolution;
    let centerColor = textureSample(inputTexture, textureSampler, input.texCoord);
    
    // Skip if soften is near zero
    if (uniforms.soften < 0.1) {
        return centerColor;
    }
    
    var sum: f32 = 0.0;
    var weight: f32 = 0.0;
    let desiredRadius = uniforms.soften * 0.2;
    
    // Gaussian-like blur with 5x5 kernel
    for (var y: i32 = -2; y <= 2; y++) {
        for (var x: i32 = -2; x <= 2; x++) {
            let dist = length(vec2f(f32(x), f32(y)));
            if (dist <= desiredRadius) {
                let offset = vec2f(f32(x), f32(y)) * pixelSize;
                let w = 1.0 / (1.0 + dist); // Simple distance falloff
                let sampleColor = textureSample(inputTexture, textureSampler, input.texCoord + offset);
                sum += sampleColor.a * w;
                weight += w;
            }
        }
    }
    
    let blurredAlpha = sum / max(weight, 0.001);
    
    return vec4f(centerColor.rgb, blurredAlpha);
}
