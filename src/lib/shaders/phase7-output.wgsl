// Phase 7: Output Shader
// Final pass: Renders to screen with output mode selection

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) texCoord: vec2f,
};

struct OutputUniforms {
    outputMode: i32,
    _padding1: f32,
    _padding2: f32,
    _padding3: f32,
};

@group(0) @binding(0) var textureSampler: sampler;
@group(0) @binding(1) var inputTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: OutputUniforms;

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
    let color = textureSample(inputTexture, textureSampler, input.texCoord);
    let alpha = color.a;
    
    if (uniforms.outputMode == 0) {
        // Composite mode
        return vec4f(color.rgb, alpha);
    } else if (uniforms.outputMode == 1) {
        // Alpha channel mode (grayscale)
        return vec4f(vec3f(alpha), 1.0);
    } else if (uniforms.outputMode == 2) {
        // Status mode (color-coded quality)
        var statusColor: vec3f;
        if (alpha > 0.95) {
            statusColor = vec3f(1.0); // White: fully opaque
        } else if (alpha < 0.05) {
            statusColor = vec3f(0.0); // Black: fully transparent
        } else if (alpha > 0.7) {
            statusColor = vec3f(0.3, 0.5, 1.0); // Blue: acceptable
        } else if (alpha > 0.4) {
            statusColor = vec3f(1.0, 1.0, 0.0); // Yellow: marginal
        } else {
            statusColor = vec3f(1.0, 0.0, 0.0); // Red: poor quality
        }
        return vec4f(statusColor, 1.0);
    }
    
    return vec4f(color.rgb, alpha);
}
