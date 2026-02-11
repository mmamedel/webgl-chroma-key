// Phase 7: Choke (Erosion/Dilation) Shader
// Pass 2: Applies choke to the alpha channel by sampling neighbors

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) texCoord: vec2f,
};

struct ChokeUniforms {
    resolution: vec2f,
    choke: f32,
    _padding: f32,
};

@group(0) @binding(0) var textureSampler: sampler;
@group(0) @binding(1) var inputTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: ChokeUniforms;

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
    
    // Skip if choke is near zero
    if (abs(uniforms.choke) < 0.1) {
        return centerColor;
    }
    
    var result = centerColor.a;
    let radius = abs(uniforms.choke) * 0.15;
    
    // Sample 5x5 neighborhood
    if (uniforms.choke > 0.0) {
        // Positive = erosion (take minimum)
        result = 1.0;
        for (var y: i32 = -2; y <= 2; y++) {
            for (var x: i32 = -2; x <= 2; x++) {
                let dist = length(vec2f(f32(x), f32(y)));
                if (dist <= radius) {
                    let offset = vec2f(f32(x), f32(y)) * pixelSize;
                    let sampleColor = textureSample(inputTexture, textureSampler, input.texCoord + offset);
                    result = min(result, sampleColor.a);
                }
            }
        }
    } else {
        // Negative = dilation (take maximum)
        result = 0.0;
        for (var y: i32 = -2; y <= 2; y++) {
            for (var x: i32 = -2; x <= 2; x++) {
                let dist = length(vec2f(f32(x), f32(y)));
                if (dist <= radius) {
                    let offset = vec2f(f32(x), f32(y)) * pixelSize;
                    let sampleColor = textureSample(inputTexture, textureSampler, input.texCoord + offset);
                    result = max(result, sampleColor.a);
                }
            }
        }
    }
    
    return vec4f(centerColor.rgb, result);
}
