precision mediump float;

uniform sampler2D u_video;
uniform sampler2D u_background;
uniform vec2 u_resolution;
uniform vec3 u_keyColor;
uniform float u_transparency;
uniform float u_tolerance;
uniform int u_outputMode;

varying vec2 v_texCoord;

vec3 rgb2hsv(vec3 rgb) {
	float Cmax = max(rgb.r, max(rgb.g, rgb.b));
	float Cmin = min(rgb.r, min(rgb.g, rgb.b));
	float delta = Cmax - Cmin;

	vec3 hsv = vec3(0., 0., Cmax);
	
	if (Cmax > Cmin) {
		hsv.y = delta / Cmax;

		if (rgb.r == Cmax)
			hsv.x = (rgb.g - rgb.b) / delta;
		else {
			if (rgb.g == Cmax)
				hsv.x = 2. + (rgb.b - rgb.r) / delta;
			else
				hsv.x = 4. + (rgb.r - rgb.g) / delta;
		}
		hsv.x = fract(hsv.x / 6.);
	}
	return hsv;
}

float chromaKey(vec3 color) {
	vec3 hsv = rgb2hsv(color);
	vec3 target = rgb2hsv(u_keyColor);
	
	// Tolerance affects weight multiplication
	float tolFactor = 1.0 + (u_tolerance - 50.0) * 0.02;
	vec3 weights = vec3(4.0, 1.0, 2.0) * tolFactor;
	
	// Weighted distance in HSV space
	vec3 diff = target - hsv;
	
	// Handle hue wraparound (hue is circular 0-1)
	if (abs(diff.x) > 0.5) {
		diff.x = diff.x - sign(diff.x);
	}
	
	float dist = length(weights * diff);
	
	// Transparency affects the slope/threshold
	// Original formula: 1 - clamp(3*dist - 1.5, 0, 1)
	// At default (50): slope=3.0, offset=1.5
	float slope = 3.0 + (u_transparency - 50.0) * 0.06;
	float offset = 1.5 - (u_transparency - 50.0) * 0.03;
	
	// Linear ramp formula (matches original)
	// Returns 0 for green (transparent), 1 for subject (opaque)
	return clamp(slope * dist - offset, 0.0, 1.0);
}

vec3 changeSaturation(vec3 color, float saturation) {
	float luma = dot(vec3(0.213, 0.715, 0.072) * color, vec3(1.));
	return mix(vec3(luma), color, saturation);
}

void main() {
	vec2 uv = v_texCoord;
	
	vec3 color = texture2D(u_video, uv).rgb;
	vec3 bg = texture2D(u_background, vec2(1.0 - uv.x, uv.y)).rgb;
	
	float alpha = chromaKey(color);
	
	// Output mode selection
	if (u_outputMode == 1) {
		// Alpha Channel mode (grayscale)
		gl_FragColor = vec4(vec3(alpha), 1.0);
	} else {
		// Composite mode
		color = changeSaturation(color, 0.5);
		color = mix(bg, color, alpha);
		gl_FragColor = vec4(color, 1.0);
	}
}
