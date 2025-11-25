<script lang="ts">
  import { onMount } from "svelte";
  import vertShader from "$lib/shaders/basic.vert?raw";
  import fragShader from "$lib/shaders/phase4.frag?raw";

  // State
  let canvas: HTMLCanvasElement;
  let video: HTMLVideoElement;
  let isPlaying = $state<boolean>(false);
  let currentTime = $state<number>(0);
  let duration = $state<number>(0);
  let seeking = $state<boolean>(false);

  // Phase 1 Parameters
  let keyColor = $state<{ r: number; g: number; b: number }>({
    r: 0.157,
    g: 0.576,
    b: 0.129,
  }); // Default green
  let transparency = $state<number>(50.0);
  let tolerance = $state<number>(50.0);
  let outputMode = $state<number>(0); // 0=Composite, 1=Alpha Channel
  let currentPreset = $state<string>("default");

  // Phase 2 Parameters: Matte Generation
  let highlight = $state<number>(50.0); // 0-100, affects bright areas
  let shadow = $state<number>(50.0); // 0-100, affects dark areas
  let pedestal = $state<number>(0.0); // 0-100, shifts entire alpha range

  // Phase 4 Parameters: Spill Suppression
  let spillSuppression = $state<number>(30.0); // 0-100, amount of color spill removal

  // WebGL context and program
  let gl = $state<WebGLRenderingContext | null>(null);
  let program = $state<WebGLProgram | null>(null);
  let uniforms = $state<Record<string, WebGLUniformLocation | null>>({});

  function createShader(
    gl: WebGLRenderingContext,
    type: number,
    source: string
  ): WebGLShader | null {
    const shader = gl.createShader(type);
    if (!shader) {
      throw new Error("Failed to create shader");
    }
    gl.shaderSource(shader, source);
    gl.compileShader(shader);

    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      console.error("Shader compile error:", gl.getShaderInfoLog(shader));
      gl.deleteShader(shader);
      return null;
    }

    return shader;
  }

  function createProgram(
    gl: WebGLRenderingContext,
    vertexShader: WebGLShader,
    fragmentShader: WebGLShader
  ): WebGLProgram | null {
    const program = gl.createProgram();
    if (!program) {
      throw new Error("Failed to create program");
    }
    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);
    gl.linkProgram(program);

    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      console.error("Program link error:", gl.getProgramInfoLog(program));
      gl.deleteProgram(program);
      return null;
    }

    return program;
  }

  function setupTexture(
    gl: WebGLRenderingContext,
    image: HTMLImageElement | HTMLVideoElement
  ): WebGLTexture | null {
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);

    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RGBA,
      1,
      1,
      0,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      new Uint8Array([0, 0, 0, 255])
    );

    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    if (image instanceof HTMLImageElement) {
      if (image.complete) {
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(
          gl.TEXTURE_2D,
          0,
          gl.RGBA,
          gl.RGBA,
          gl.UNSIGNED_BYTE,
          image
        );
      } else {
        image.onload = () => {
          gl.bindTexture(gl.TEXTURE_2D, texture);
          gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            image
          );
        };
      }
    }

    return texture;
  }

  function updateVideoTexture(
    gl: WebGLRenderingContext,
    texture: WebGLTexture,
    video: HTMLVideoElement
  ): void {
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, video);
  }

  function applyPreset(preset: string): void {
    currentPreset = preset;
    if (preset === "default") {
      transparency = 50.0;
      tolerance = 50.0;
    } else if (preset === "aggressive") {
      transparency = 70.0;
      tolerance = 60.0;
    }
  }

  function pickKeyColor() {
    if (!video || !video.readyState) return;

    // Create a temporary canvas to sample pixel
    const tempCanvas = document.createElement("canvas");
    tempCanvas.width = video.videoWidth;
    tempCanvas.height = video.videoHeight;
    const ctx = tempCanvas.getContext("2d");
    if (!ctx) {
      throw new Error("Failed to get 2D context");
    }
    ctx.drawImage(video, 0, 0);

    // Sample center pixel
    const x = Math.floor(video.videoWidth / 2);
    const y = Math.floor(video.videoHeight / 2);
    const pixel = ctx.getImageData(x, y, 1, 1).data;

    keyColor = {
      r: pixel[0] / 255,
      g: pixel[1] / 255,
      b: pixel[2] / 255,
    };
    currentPreset = "custom";
  }

  // Watch for parameter changes and mark as custom
  $effect(() => {
    // If user manually adjusts, mark as custom
    if (currentPreset !== "custom") {
      const _ = transparency + tolerance; // Access to trigger effect
      // Don't change preset on initialization
      if (gl) {
        setTimeout(() => {
          if (currentPreset !== "custom") {
            currentPreset = "custom";
          }
        }, 100);
      }
    }
  });

  onMount(() => {
    gl = canvas.getContext("webgl", { alpha: true, premultipliedAlpha: false });
    if (!gl) {
      throw new Error("WebGL not supported");
    }

    // Enable blending for transparency
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    // Create shaders and program
    const vertexShader = createShader(gl, gl.VERTEX_SHADER, vertShader);
    const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fragShader);

    if (!vertexShader || !fragmentShader) {
      throw new Error("Failed to create shaders");
    }

    program = createProgram(gl, vertexShader, fragmentShader);
    if (!program) {
      throw new Error("Failed to create program");
    }

    // Set up geometry
    const positions = new Float32Array([
      -1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1,
    ]);

    const texCoords = new Float32Array([0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0]);

    const positionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);

    const texCoordBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, texCoords, gl.STATIC_DRAW);

    // Get locations
    const positionLocation = gl.getAttribLocation(program!, "a_position");
    const texCoordLocation = gl.getAttribLocation(program!, "a_texCoord");

    uniforms = {
      video: gl.getUniformLocation(program!, "u_video"),
      resolution: gl.getUniformLocation(program!, "u_resolution"),
      keyColor: gl.getUniformLocation(program!, "u_keyColor"),
      transparency: gl.getUniformLocation(program!, "u_transparency"),
      tolerance: gl.getUniformLocation(program!, "u_tolerance"),
      outputMode: gl.getUniformLocation(program!, "u_outputMode"),
      highlight: gl.getUniformLocation(program!, "u_highlight"),
      shadow: gl.getUniformLocation(program!, "u_shadow"),
      pedestal: gl.getUniformLocation(program!, "u_pedestal"),
      spillSuppression: gl.getUniformLocation(program!, "u_spillSuppression"),
    };

    // Load video texture
    const videoTexture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, videoTexture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    // Render loop
    function render() {
      if (!gl || !program) return;

      if (video && video.readyState >= video.HAVE_CURRENT_DATA) {
        if (
          canvas.width !== video.videoWidth ||
          canvas.height !== video.videoHeight
        ) {
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
        }

        gl.viewport(0, 0, canvas.width, canvas.height);
        updateVideoTexture(gl, videoTexture, video);

        // Clear with transparency (alpha = 0)
        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.useProgram(program);

        // Set up attributes
        gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
        gl.enableVertexAttribArray(positionLocation);
        gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

        gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
        gl.enableVertexAttribArray(texCoordLocation);
        gl.vertexAttribPointer(texCoordLocation, 2, gl.FLOAT, false, 0, 0);

        // Set uniforms
        gl.uniform2f(uniforms.resolution, canvas.width, canvas.height);
        gl.uniform3f(uniforms.keyColor, keyColor.r, keyColor.g, keyColor.b);
        gl.uniform1f(uniforms.transparency, transparency);
        gl.uniform1f(uniforms.tolerance, tolerance);
        gl.uniform1i(uniforms.outputMode, outputMode);

        // Phase 2 uniforms
        gl.uniform1f(uniforms.highlight, highlight);
        gl.uniform1f(uniforms.shadow, shadow);
        gl.uniform1f(uniforms.pedestal, pedestal);

        // Phase 4 uniforms
        gl.uniform1f(uniforms.spillSuppression, spillSuppression);

        // Bind video texture
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, videoTexture);
        gl.uniform1i(uniforms.video, 0);

        gl.drawArrays(gl.TRIANGLES, 0, 6);
      }

      requestAnimationFrame(render);
    }

    render();
  });

  function togglePlayPause(): void {
    if (!video) return;
    if (video.paused) {
      video.play();
      isPlaying = true;
    } else {
      video.pause();
      isPlaying = false;
    }
  }

  function handleTimeUpdate(): void {
    if (!seeking && video) {
      currentTime = video.currentTime;
    }
  }

  function handleLoadedMetadata(): void {
    if (video) {
      duration = video.duration;
    }
  }

  function handleSeek(event: MouseEvent): void {
    if (!video) return;
    const timeline = event.currentTarget as HTMLElement;
    const rect = timeline.getBoundingClientRect();
    const pos = (event.clientX - rect.left) / rect.width;
    video.currentTime = pos * duration;
    currentTime = video.currentTime;
  }

  function handleSeekStart(): void {
    seeking = true;
  }

  function handleSeekEnd(): void {
    seeking = false;
  }

  function formatTime(time: number): string {
    const minutes = Math.floor(time / 60);
    const seconds = Math.floor(time % 60);
    return `${minutes}:${seconds.toString().padStart(2, "0")}`;
  }

  function resetToDefaults(): void {
    keyColor = { r: 0.157, g: 0.576, b: 0.129 };
    applyPreset("default");
  }
</script>

<main>
  <div class="header">
    <h1>Phase 4: Spill Suppression</h1>
    <div class="nav-links">
      <a href="/phase3" class="back-link">← Phase 3</a>
      <a href="/phase2" class="back-link">Phase 2</a>
      <a href="/phase1" class="back-link">Phase 1</a>
    </div>
  </div>

  <div class="container">
    <div class="video-section">
      <div class="video-container">
        <div class="background-layer"></div>
        <video
          bind:this={video}
          src="/060_INSIGHT-4_Paragraph_20251117_113546.mp4"
          loop
          muted
          crossorigin="anonymous"
          style="display: none;"
          ontimeupdate={handleTimeUpdate}
          onloadedmetadata={handleLoadedMetadata}
          onloadeddata={() => {
            if (video) {
              canvas.width = video.videoWidth;
              canvas.height = video.videoHeight;
            }
          }}
        ></video>
        <canvas bind:this={canvas} width="1280" height="720"></canvas>
      </div>

      <div class="controls">
        <button onclick={togglePlayPause}>
          {isPlaying ? "⏸ Pause" : "▶ Play"}
        </button>

        <div class="timeline-container">
          <span class="time">{formatTime(currentTime)}</span>
          <div
            class="timeline"
            role="slider"
            tabindex="0"
            aria-label="Video timeline"
            aria-valuemin="0"
            aria-valuemax={duration}
            aria-valuenow={currentTime}
            onclick={handleSeek}
            onmousedown={handleSeekStart}
            onmouseup={handleSeekEnd}
            onkeydown={(e) => {
              if (e.key === "ArrowLeft") video.currentTime -= 5;
              if (e.key === "ArrowRight") video.currentTime += 5;
            }}
          >
            <div
              class="timeline-progress"
              style="width: {duration > 0
                ? (currentTime / duration) * 100
                : 0}%"
            ></div>
          </div>
          <span class="time">{formatTime(duration)}</span>
        </div>
      </div>
    </div>

    <div class="controls-panel">
      <div class="section">
        <h2>Preset</h2>
        <div class="preset-buttons">
          <button
            class:active={currentPreset === "default"}
            onclick={() => applyPreset("default")}
          >
            Default
          </button>
          <button
            class:active={currentPreset === "aggressive"}
            onclick={() => applyPreset("aggressive")}
          >
            Aggressive
          </button>
          <button class:active={currentPreset === "custom"} disabled>
            Custom
          </button>
        </div>
      </div>

      <div class="section">
        <h2>Key Color</h2>
        <div class="key-color-controls">
          <div
            class="color-preview"
            style="background-color: rgb({Math.round(
              keyColor.r * 255
            )}, {Math.round(keyColor.g * 255)}, {Math.round(keyColor.b * 255)})"
          ></div>
          <div class="color-values">
            <span>R: {keyColor.r.toFixed(3)}</span>
            <span>G: {keyColor.g.toFixed(3)}</span>
            <span>B: {keyColor.b.toFixed(3)}</span>
          </div>
          <button onclick={pickKeyColor}> 🎨 Pick from Center </button>
        </div>
      </div>

      <div class="section">
        <h2>Matte Generation</h2>

        <div class="control">
          <div class="control-label">
            <span class="label-text">Transparency</span>
            <span class="value">{transparency.toFixed(1)}</span>
          </div>
          <input
            type="range"
            bind:value={transparency}
            min="0"
            max="100"
            step="0.1"
            aria-label="Transparency"
          />
          <p class="help">
            Adjusts threshold between transparent and opaque areas
          </p>
        </div>

        <div class="control">
          <div class="control-label">
            <span class="label-text">Tolerance</span>
            <span class="value">{tolerance.toFixed(1)}</span>
          </div>
          <input
            type="range"
            bind:value={tolerance}
            min="0"
            max="100"
            step="0.1"
            aria-label="Tolerance"
          />
          <p class="help">
            Expands/contracts range of colors considered as key color
          </p>
        </div>
      </div>

      <div class="section">
        <h2>Phase 2: Matte Controls</h2>

        <div class="control">
          <div class="control-label">
            <span class="label-text">Highlight</span>
            <span class="value">{highlight.toFixed(1)}</span>
          </div>
          <input
            type="range"
            bind:value={highlight}
            min="0"
            max="100"
            step="0.1"
            aria-label="Highlight"
          />
          <p class="help">
            Controls transparency in bright areas. 50 = neutral, higher = more
            transparent
          </p>
        </div>

        <div class="control">
          <div class="control-label">
            <span class="label-text">Shadow</span>
            <span class="value">{shadow.toFixed(1)}</span>
          </div>
          <input
            type="range"
            bind:value={shadow}
            min="0"
            max="100"
            step="0.1"
            aria-label="Shadow"
          />
          <p class="help">
            Controls transparency in dark areas. 50 = neutral, higher = more
            opaque
          </p>
        </div>

        <div class="control">
          <div class="control-label">
            <span class="label-text">Pedestal</span>
            <span class="value">{pedestal.toFixed(1)}</span>
          </div>
          <input
            type="range"
            bind:value={pedestal}
            min="0"
            max="100"
            step="0.1"
            aria-label="Pedestal"
          />
          <p class="help">
            Shifts entire alpha range. Higher values make everything more opaque
          </p>
        </div>
      </div>

      <div class="section">
        <h2>Phase 4: Spill Suppression</h2>

        <div class="control">
          <div class="control-label">
            <span class="label-text">Spill Amount</span>
            <span class="value">{spillSuppression.toFixed(1)}</span>
          </div>
          <input
            type="range"
            bind:value={spillSuppression}
            min="0"
            max="100"
            step="0.1"
            aria-label="Spill Suppression"
          />
          <p class="help">
            Removes color spill from keyed background. 0 = no suppression
            (natural colors), higher = more removal. Only affects edges near key
            color.
          </p>
        </div>
      </div>

      <div class="section">
        <h2>Output Mode</h2>
        <div class="output-buttons">
          <button
            class:active={outputMode === 0}
            onclick={() => (outputMode = 0)}
          >
            Composite
          </button>
          <button
            class:active={outputMode === 1}
            onclick={() => (outputMode = 1)}
          >
            Alpha Channel
          </button>
          <button
            class:active={outputMode === 2}
            onclick={() => (outputMode = 2)}
          >
            Status
          </button>
        </div>
        <p class="help">
          {outputMode === 0
            ? "Final keyed result over background"
            : outputMode === 1
              ? "Grayscale matte (white=opaque, black=transparent)"
              : "Color-coded status: Green=transparent, Red=partial, White=opaque"}
        </p>
      </div>

      <div class="section">
        <button class="reset-button" onclick={resetToDefaults}>
          Reset to Defaults
        </button>
      </div>

      <div class="info-box">
        <h3>✅ Phase 4: Spill Suppression</h3>
        <ul>
          <li>
            <strong>Configurable Spill Removal</strong> - Control amount of color
            spill suppression
          </li>
          <li>
            <strong>Targeted Application</strong> - Only affects pixels near key
            color (not entire image)
          </li>
          <li>
            <strong>Edge-Aware</strong> - Maximum effect on edges, preserves fully
            opaque areas
          </li>
          <li>
            <strong>Fixes Desaturation</strong> - Set to 0 for natural colors, increase
            as needed
          </li>
        </ul>
        <p class="next">
          <strong>Complete Feature Set:</strong> All matte controls, output modes,
          and targeted spill suppression
        </p>
        <p class="next">
          <strong>✨ This fixes the desaturation issue!</strong> Lower spill suppression
          to restore natural saturation.
        </p>
      </div>
    </div>
  </div>
</main>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    font-family:
      system-ui,
      -apple-system,
      sans-serif;
    background: #1a1a1a;
    color: #fff;
  }

  main {
    max-width: 1600px;
    margin: 0 auto;
    padding: 2rem;
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
  }

  h1 {
    margin: 0;
    color: #4caf50;
    font-size: 2rem;
  }

  .nav-links {
    display: flex;
    gap: 1rem;
  }

  .back-link {
    color: #4caf50;
    text-decoration: none;
    font-weight: 600;
    padding: 0.5rem 1rem;
    border: 2px solid #4caf50;
    border-radius: 4px;
    transition: all 0.2s;
  }

  .back-link:hover {
    background: #4caf50;
    color: #1a1a1a;
  }

  .container {
    display: grid;
    grid-template-columns: 2fr 1fr;
    gap: 2rem;
  }

  .video-section {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .video-container {
    position: relative;
    background: #000;
    border-radius: 8px;
    overflow: hidden;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
    display: flex;
    justify-content: center;
    align-items: center;
  }

  .background-layer {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background-image: url("/blue.jpg");
    background-size: cover;
    background-position: center;
    z-index: 0;
  }

  canvas {
    position: relative;
    z-index: 1;
    max-width: 100%;
    height: auto;
    display: block;
  }

  .controls {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1rem;
    margin-bottom: 2rem;
  }

  .timeline-container {
    display: flex;
    align-items: center;
    gap: 1rem;
    width: 100%;
    max-width: 800px;
  }

  .timeline {
    flex: 1;
    height: 8px;
    background: #444;
    border-radius: 4px;
    cursor: pointer;
    position: relative;
    overflow: hidden;
  }

  .timeline:hover {
    background: #555;
  }

  .timeline-progress {
    height: 100%;
    background: #4caf50;
    border-radius: 4px;
    transition: width 0.1s linear;
  }

  .time {
    font-size: 0.9rem;
    color: #ccc;
    min-width: 45px;
    text-align: center;
    font-variant-numeric: tabular-nums;
  }

  .controls-panel {
    background: #2a2a2a;
    border-radius: 8px;
    padding: 1.5rem;
    max-height: 90vh;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }

  .section {
    border-bottom: 1px solid #3a3a3a;
    padding-bottom: 1.5rem;
  }

  .section:last-child {
    border-bottom: none;
    padding-bottom: 0;
  }

  h2 {
    margin: 0 0 1rem 0;
    font-size: 1.1rem;
    color: #4caf50;
  }

  h3 {
    margin: 0 0 0.5rem 0;
    color: #4caf50;
  }

  .preset-buttons,
  .output-buttons {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 0.5rem;
  }

  button {
    padding: 0.75rem 1rem;
    font-size: 0.9rem;
    font-weight: 600;
    background: #3a3a3a;
    color: white;
    border: 2px solid transparent;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s;
  }

  button:hover:not(:disabled) {
    background: #4a4a4a;
  }

  button.active {
    background: #4caf50;
    border-color: #4caf50;
    color: #1a1a1a;
  }

  button:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .key-color-controls {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .color-preview {
    width: 100%;
    height: 60px;
    border-radius: 4px;
    border: 2px solid #3a3a3a;
  }

  .color-values {
    display: flex;
    justify-content: space-between;
    font-family: monospace;
    font-size: 0.85rem;
    color: #888;
  }

  .control {
    margin-bottom: 1.5rem;
  }

  .control:last-child {
    margin-bottom: 0;
  }

  .control-label {
    display: flex;
    justify-content: space-between;
    margin-bottom: 0.5rem;
    font-weight: 600;
  }

  .label-text {
    color: #ddd;
  }

  .value {
    color: #4caf50;
    font-family: monospace;
  }

  input[type="range"] {
    width: 100%;
    height: 6px;
    background: #3a3a3a;
    border-radius: 3px;
    outline: none;
    -webkit-appearance: none;
    appearance: none;
  }

  input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 18px;
    height: 18px;
    background: #4caf50;
    cursor: pointer;
    border-radius: 50%;
  }

  input[type="range"]::-moz-range-thumb {
    width: 18px;
    height: 18px;
    background: #4caf50;
    cursor: pointer;
    border-radius: 50%;
    border: none;
  }

  .help {
    margin: 0.5rem 0 0 0;
    font-size: 0.85rem;
    color: #888;
    line-height: 1.4;
  }

  .reset-button {
    width: 100%;
    background: #d32f2f;
    border-color: #d32f2f;
  }

  .reset-button:hover {
    background: #b71c1c;
    border-color: #b71c1c;
  }

  .info-box {
    background: #1e1e1e;
    padding: 1rem;
    border-radius: 4px;
    border-left: 4px solid #4caf50;
  }

  .info-box ul {
    margin: 0.5rem 0;
    padding-left: 1.5rem;
  }

  .info-box li {
    margin: 0.25rem 0;
    font-size: 0.9rem;
  }

  .next {
    margin: 1rem 0 0 0;
    padding-top: 1rem;
    border-top: 1px solid #3a3a3a;
    color: #888;
    font-size: 0.9rem;
  }

  @media (max-width: 1200px) {
    .container {
      grid-template-columns: 1fr;
    }

    .controls-panel {
      max-height: none;
    }
  }
</style>
