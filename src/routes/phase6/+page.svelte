<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import shaderCode from "$lib/shaders/phase6.wgsl?raw";

  // State
  let canvas: HTMLCanvasElement;
  let video: HTMLVideoElement;
  let isPlaying = $state<boolean>(false);
  let currentTime = $state<number>(0);
  let duration = $state<number>(0);
  let seeking = $state<boolean>(false);
  let webgpuSupported = $state<boolean>(true);
  let errorMessage = $state<string>("");

  // Phase 1 Parameters
  let keyColor = $state<{ r: number; g: number; b: number }>({
    r: 0.157,
    g: 0.576,
    b: 0.129,
  }); // Default green
  let keyColorHex = $state<string>("#28933d"); // Hex representation for color picker
  let transparency = $state<number>(50.0);
  let tolerance = $state<number>(50.0);
  let outputMode = $state<number>(0); // 0=Composite, 1=Alpha Channel
  let currentPreset = $state<string>("default");

  // Phase 2 Parameters: Matte Generation
  let highlight = $state<number>(50.0); // 0-100, affects bright areas
  let shadow = $state<number>(50.0); // 0-100, affects dark areas
  let pedestal = $state<number>(0.0); // 0-100, shifts entire alpha range

  // Phase 4 Parameters: Spill Suppression
  let spillSuppression = $state<number>(0.0); // 0-100, amount of color spill removal

  // Phase 5 Parameters: Matte Cleanup
  let contrast = $state<number>(0.0); // 0-100, pushes mid-tones toward black/white
  let midPoint = $state<number>(50.0); // 0-100, pivot point for contrast
  let choke = $state<number>(0.0); // -20 to 20, negative=expand, positive=shrink (not implemented in WebGPU external texture)
  let soften = $state<number>(0.0); // 0-20, blur amount for edges (not implemented in WebGPU external texture)

  // Video source
  let videoSrc = $state<string>("");
  let uploadedFileName = $state<string>("");

  // Color picker state
  let colorInput: HTMLInputElement;
  let isPickingFromVideo = $state<boolean>(false);

  // Render loop optimization
  let animationFrameId: number | null = null;
  let shouldRender = true;

  // WebGPU context
  let device: GPUDevice | null = null;
  let context: GPUCanvasContext | null = null;
  let pipeline: GPURenderPipeline | null = null;
  let sampler: GPUSampler | null = null;
  let uniformBuffer: GPUBuffer | null = null;

  // Uniform buffer layout (must match WGSL struct with proper alignment)
  const UNIFORM_BUFFER_SIZE = 80; // Aligned to 16 bytes

  function applyPreset(preset: string): void {
    currentPreset = preset;
    if (preset === "default") {
      transparency = 50.0;
      tolerance = 50.0;
      highlight = 50.0;
      shadow = 50.0;
      pedestal = 0.0;
      spillSuppression = 0.0;
      contrast = 0.0;
      midPoint = 50.0;
      choke = 0.0;
      soften = 0.0;
    } else if (preset === "aggressive") {
      transparency = 70.0;
      tolerance = 60.0;
      highlight = 60.0;
      shadow = 60.0;
      pedestal = 5.0;
      spillSuppression = 80.0;
      contrast = 50.0;
      midPoint = 50.0;
      choke = 2.0;
      soften = 3.0;
    }
  }

  function handleFileUpload(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (file) {
      // Revoke previous object URL to avoid memory leaks
      if (videoSrc && videoSrc.startsWith("blob:")) {
        URL.revokeObjectURL(videoSrc);
      }

      // Create new object URL
      videoSrc = URL.createObjectURL(file);
      uploadedFileName = file.name;

      // Reset video state
      if (video) {
        video.load();
        isPlaying = false;
      }
    }
  }

  // Sync hex color to RGB
  function hexToRgb(hex: string): { r: number; g: number; b: number } {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    return result
      ? {
          r: parseInt(result[1], 16) / 255,
          g: parseInt(result[2], 16) / 255,
          b: parseInt(result[3], 16) / 255,
        }
      : { r: 0, g: 0, b: 0 };
  }

  // Sync RGB to hex color
  function rgbToHex(r: number, g: number, b: number): string {
    const toHex = (val: number) => {
      const hex = Math.round(val * 255).toString(16);
      return hex.length === 1 ? "0" + hex : hex;
    };
    return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
  }

  // Update RGB when hex changes
  $effect(() => {
    if (keyColorHex) {
      keyColor = hexToRgb(keyColorHex);
    }
  });

  // EyeDropper API for picking color from anywhere on screen
  async function useEyeDropper() {
    if (!video || !videoSrc) return;

    isPickingFromVideo = true;
    shouldRender = true;

    // Check if EyeDropper API is supported
    if (!("EyeDropper" in window)) {
      alert(
        "EyeDropper API is not supported in your browser. Please use Chrome/Edge 95+ or try the Color Picker instead."
      );
      isPickingFromVideo = false;
      return;
    }

    try {
      // @ts-ignore - EyeDropper is experimental
      const eyeDropper = new EyeDropper();
      const result = await eyeDropper.open();
      keyColorHex = result.sRGBHex;
      currentPreset = "custom";
    } catch (e) {
      // User cancelled
    } finally {
      isPickingFromVideo = false;
      shouldRender = true;
    }
  }

  // Trigger re-render when parameters change (for paused video)
  $effect(() => {
    // Track all parameters that affect rendering
    const _ =
      transparency +
      tolerance +
      highlight +
      shadow +
      pedestal +
      spillSuppression +
      contrast +
      midPoint +
      choke +
      soften +
      outputMode +
      keyColor.r +
      keyColor.g +
      keyColor.b;

    // Request re-render if video is paused
    if (video && video.paused) {
      shouldRender = true;
    }
  });

  async function initWebGPU() {
    // Check WebGPU support
    if (!navigator.gpu) {
      webgpuSupported = false;
      errorMessage =
        "WebGPU is not supported in your browser. Try Chrome 113+ or Edge 113+.";
      return false;
    }

    const adapter = await navigator.gpu.requestAdapter();
    if (!adapter) {
      webgpuSupported = false;
      errorMessage = "Failed to get WebGPU adapter.";
      return false;
    }

    device = await adapter.requestDevice();
    if (!device) {
      webgpuSupported = false;
      errorMessage = "Failed to get WebGPU device.";
      return false;
    }

    // Configure canvas context
    context = canvas.getContext("webgpu");
    if (!context) {
      webgpuSupported = false;
      errorMessage = "Failed to get WebGPU canvas context.";
      return false;
    }

    const presentationFormat = navigator.gpu.getPreferredCanvasFormat();
    context.configure({
      device,
      format: presentationFormat,
      alphaMode: "premultiplied",
    });

    // Create shader module
    const shaderModule = device.createShaderModule({
      label: "Chroma Key Shader",
      code: shaderCode,
    });

    // Create render pipeline
    pipeline = device.createRenderPipeline({
      label: "Chroma Key Pipeline",
      layout: "auto",
      vertex: {
        module: shaderModule,
        entryPoint: "vs",
      },
      fragment: {
        module: shaderModule,
        entryPoint: "fs",
        targets: [
          {
            format: presentationFormat,
            blend: {
              color: {
                srcFactor: "src-alpha",
                dstFactor: "one-minus-src-alpha",
                operation: "add",
              },
              alpha: {
                srcFactor: "one",
                dstFactor: "one-minus-src-alpha",
                operation: "add",
              },
            },
          },
        ],
      },
      primitive: {
        topology: "triangle-list",
      },
    });

    // Create sampler
    sampler = device.createSampler({
      magFilter: "linear",
      minFilter: "linear",
    });

    // Create uniform buffer
    uniformBuffer = device.createBuffer({
      size: UNIFORM_BUFFER_SIZE,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    return true;
  }

  function updateUniforms() {
    if (!device || !uniformBuffer) return;

    // Create uniform data matching WGSL struct layout
    const uniformData = new ArrayBuffer(UNIFORM_BUFFER_SIZE);
    const floatView = new Float32Array(uniformData);
    const intView = new Int32Array(uniformData);

    // resolution: vec2f (offset 0)
    floatView[0] = canvas.width;
    floatView[1] = canvas.height;
    // keyColor: vec3f (offset 8, aligned to 16)
    floatView[4] = keyColor.r;
    floatView[5] = keyColor.g;
    floatView[6] = keyColor.b;
    // transparency: f32 (offset 28)
    floatView[7] = transparency;
    // tolerance: f32 (offset 32)
    floatView[8] = tolerance;
    // highlight: f32 (offset 36)
    floatView[9] = highlight;
    // shadow: f32 (offset 40)
    floatView[10] = shadow;
    // pedestal: f32 (offset 44)
    floatView[11] = pedestal;
    // spillSuppression: f32 (offset 48)
    floatView[12] = spillSuppression;
    // contrast: f32 (offset 52)
    floatView[13] = contrast;
    // midPoint: f32 (offset 56)
    floatView[14] = midPoint;
    // choke: f32 (offset 60)
    floatView[15] = choke;
    // soften: f32 (offset 64)
    floatView[16] = soften;
    // outputMode: i32 (offset 68)
    intView[17] = outputMode;
    // _padding: f32 (offset 72)
    floatView[18] = 0;

    device.queue.writeBuffer(uniformBuffer, 0, uniformData);
  }

  function render() {
    if (
      !device ||
      !context ||
      !pipeline ||
      !sampler ||
      !uniformBuffer ||
      !video
    ) {
      animationFrameId = requestAnimationFrame(render);
      return;
    }

    // Check video has valid frame data before attempting import
    const canImport =
      video.readyState >= video.HAVE_CURRENT_DATA &&
      video.videoWidth > 0 &&
      video.videoHeight > 0 &&
      (!video.paused || video.currentTime > 0);

    if (canImport) {
      try {
        // Update canvas size if needed
        if (
          canvas.width !== video.videoWidth ||
          canvas.height !== video.videoHeight
        ) {
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
        }

        // Update uniforms
        updateUniforms();

        // Import external texture from video (must be done every frame)
        const externalTexture = device.importExternalTexture({ source: video });

        // Create bind group (must be recreated every frame for external texture)
        const bindGroup = device.createBindGroup({
          layout: pipeline.getBindGroupLayout(0),
          entries: [
            { binding: 0, resource: sampler },
            { binding: 1, resource: externalTexture },
            { binding: 2, resource: { buffer: uniformBuffer } },
          ],
        });

        // Create command encoder
        const commandEncoder = device.createCommandEncoder();

        // Begin render pass
        const renderPass = commandEncoder.beginRenderPass({
          colorAttachments: [
            {
              view: context.getCurrentTexture().createView(),
              clearValue: { r: 0, g: 0, b: 0, a: 0 },
              loadOp: "clear",
              storeOp: "store",
            },
          ],
        });

        renderPass.setPipeline(pipeline);
        renderPass.setBindGroup(0, bindGroup);
        renderPass.draw(6); // 6 vertices for 2 triangles (fullscreen quad)
        renderPass.end();

        // Submit commands
        device.queue.submit([commandEncoder.finish()]);
      } catch (e) {
        // Video frame not ready yet, skip this frame
        console.debug("Skipping frame - video not ready:", e);
      }
    }

    animationFrameId = requestAnimationFrame(render);
  }

  onMount(async () => {
    const success = await initWebGPU();
    if (success) {
      render();
    }
  });

  onDestroy(() => {
    // Clean up animation frame
    if (animationFrameId !== null) {
      cancelAnimationFrame(animationFrameId);
    }

    // Clean up blob URL if it exists
    if (videoSrc && videoSrc.startsWith("blob:")) {
      URL.revokeObjectURL(videoSrc);
    }

    // Clean up WebGPU resources
    uniformBuffer?.destroy();
  });

  function togglePlayPause(): void {
    if (!video || !videoSrc) return;
    if (video.paused) {
      video.play();
      isPlaying = true;
      shouldRender = true;
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
    <h1>Phase 6: WebGPU</h1>
    <div class="nav-links">
      <a href="/phase7" class="back-link">Phase 7 (Multi-Pass) →</a>
      <a href="/phase5" class="back-link">← Phase 5 (WebGL)</a>
      <a href="/phase4" class="back-link">Phase 4</a>
    </div>
  </div>

  {#if !webgpuSupported}
    <div class="error-banner">
      <h2>WebGPU Not Available</h2>
      <p>{errorMessage}</p>
      <p>Please use <a href="/phase5">Phase 5 (WebGL)</a> instead.</p>
    </div>
  {:else}
    <div class="container">
      <div class="video-section">
        <div class="video-container">
          <div class="background-layer"></div>
          {#if videoSrc}
            <video
              bind:this={video}
              src={videoSrc}
              loop
              muted
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
          {:else}
            <video bind:this={video} style="display: none;"></video>
          {/if}
          <canvas bind:this={canvas} width="1280" height="720"></canvas>
        </div>

        <div class="controls">
          <div class="filename-display" class:placeholder={!uploadedFileName}>
            {uploadedFileName || "No file loaded"}
          </div>

          <div class="control-buttons">
            <label class="load-video-btn">
              <input
                type="file"
                accept="video/*"
                onchange={handleFileUpload}
                style="display: none;"
              />
              📁 Load
            </label>
            <button onclick={togglePlayPause} disabled={!videoSrc}>
              {isPlaying ? "⏸ Pause" : "▶ Play"}
            </button>
          </div>

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
          <h2>Key Color</h2>
          <div class="key-color-controls">
            <div class="premiere-color-picker">
              <div class="color-swatch-container">
                <div
                  class="color-swatch"
                  style="background-color: {keyColorHex};"
                  onclick={() => colorInput?.click()}
                  onkeydown={(e) => e.key === "Enter" && colorInput?.click()}
                  role="button"
                  tabindex="0"
                  title="Click to pick color"
                ></div>
                <button
                  class="eyedropper-btn"
                  onclick={useEyeDropper}
                  disabled={!videoSrc}
                  title="Pick color from video"
                >
                  💧
                </button>
              </div>
              <div class="color-info">
                <input
                  type="text"
                  class="hex-input"
                  bind:value={keyColorHex}
                  onchange={() => (currentPreset = "custom")}
                  placeholder="#000000"
                />
                <div class="rgb-values">
                  <span>R: {Math.round(keyColor.r * 255)}</span>
                  <span>G: {Math.round(keyColor.g * 255)}</span>
                  <span>B: {Math.round(keyColor.b * 255)}</span>
                </div>
              </div>
            </div>

            <input
              type="color"
              bind:this={colorInput}
              value={keyColorHex || "#28933d"}
              oninput={(e) => {
                keyColorHex = e.currentTarget.value;
                currentPreset = "custom";
              }}
              style="position: absolute; opacity: 0; pointer-events: none;"
            />
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
          <h2>Matte Controls</h2>

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
              Shifts entire alpha range. Higher values make everything more
              opaque
            </p>
          </div>
        </div>

        <div class="section">
          <h2>Spill Suppression</h2>

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
              Removes green/blue color spill from background onto subject.
            </p>
          </div>
        </div>

        <div class="section">
          <h2>Matte Cleanup</h2>

          <div class="control">
            <div class="control-label">
              <span class="label-text">Contrast</span>
              <span class="value">{contrast.toFixed(1)}</span>
            </div>
            <input
              type="range"
              bind:value={contrast}
              min="0"
              max="200"
              step="0.1"
              aria-label="Contrast"
            />
            <p class="help">
              Pushes semi-transparent pixels toward black or white.
            </p>
          </div>

          <div class="control">
            <div class="control-label">
              <span class="label-text">Mid Point</span>
              <span class="value">{midPoint.toFixed(1)}</span>
            </div>
            <input
              type="range"
              bind:value={midPoint}
              min="0"
              max="100"
              step="0.1"
              aria-label="Mid Point"
            />
            <p class="help">
              Pivot point for contrast. Below 50 = favors transparency.
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
          <h3>🚀 Phase 6: WebGPU Implementation</h3>
          <ul>
            <li>
              <strong>importExternalTexture</strong> - Zero-copy video frame import
            </li>
            <li>
              <strong>texture_external</strong> - Optimized video texture type
            </li>
            <li>
              <strong>WGSL Shaders</strong> - Modern shader language
            </li>
          </ul>
          <p class="next">
            <strong>Note:</strong> Choke and Soften effects require multi-pass rendering
            which isn't supported with external textures. Use Phase 5 (WebGL) for
            those features.
          </p>
          <p class="next">
            <strong>Performance:</strong> WebGPU's importExternalTexture provides
            zero-copy video frame access, making it more efficient than WebGL's texImage2D.
          </p>
        </div>
      </div>
    </div>
  {/if}
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
    color: #9c27b0;
    font-size: 2rem;
  }

  .nav-links {
    display: flex;
    gap: 1rem;
  }

  .back-link {
    color: #9c27b0;
    text-decoration: none;
    font-weight: 600;
    padding: 0.5rem 1rem;
    border: 2px solid #9c27b0;
    border-radius: 4px;
    transition: all 0.2s;
  }

  .back-link:hover {
    background: #9c27b0;
    color: #1a1a1a;
  }

  .error-banner {
    background: #d32f2f;
    padding: 2rem;
    border-radius: 8px;
    text-align: center;
  }

  .error-banner a {
    color: #fff;
    text-decoration: underline;
  }

  .container {
    display: grid;
    grid-template-columns: 2fr 1fr;
    gap: 2rem;
    grid-auto-rows: min-content;
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
    min-height: 400px;
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
    max-width: 100%;
    height: auto;
    display: block;
    position: relative;
    z-index: 1;
  }

  .premiere-color-picker {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem;
    background: #2a2a2a;
    border-radius: 4px;
    border: 1px solid #3a3a3a;
  }

  .color-swatch-container {
    display: flex;
    align-items: center;
    gap: 2px;
    background: #1a1a1a;
    border-radius: 3px;
    padding: 2px;
  }

  .color-swatch {
    width: 40px;
    height: 40px;
    border-radius: 2px;
    cursor: pointer;
    border: 1px solid #4a4a4a;
    transition: border-color 0.2s;
  }

  .color-swatch:hover {
    border-color: #6a6a6a;
  }

  .color-swatch:focus {
    outline: 2px solid #0078d4;
    outline-offset: 2px;
  }

  .eyedropper-btn {
    width: 32px;
    height: 40px;
    background: #3a3a3a;
    border: 1px solid #4a4a4a;
    border-radius: 2px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 16px;
    transition: all 0.2s;
  }

  .eyedropper-btn:hover:not(:disabled) {
    background: #4a4a4a;
    color: #ffffff;
  }

  .eyedropper-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .color-info {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .hex-input {
    background: #1a1a1a;
    border: 1px solid #3a3a3a;
    border-radius: 3px;
    padding: 0.25rem 0.5rem;
    color: #cccccc;
    font-family: monospace;
    font-size: 13px;
    width: 90px;
  }

  .hex-input:focus {
    outline: none;
    border-color: #0078d4;
  }

  .rgb-values {
    display: flex;
    gap: 0.5rem;
    font-family: monospace;
    font-size: 11px;
    color: #888888;
  }

  .rgb-values span {
    min-width: 45px;
  }

  .controls {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1rem;
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
    background: #9c27b0;
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

  .control-buttons {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    flex-wrap: wrap;
  }

  .load-video-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0.75rem 1rem;
    font-size: 0.9rem;
    font-weight: 600;
    background: #3a3a3a;
    color: white;
    border: 2px solid transparent;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s;
    box-sizing: border-box;
    line-height: 1;
  }

  .load-video-btn:hover {
    background: #4a4a4a;
  }

  .filename-display {
    color: #9c27b0;
    font-size: 0.9rem;
    font-weight: 500;
    text-align: center;
    margin-bottom: 0.5rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .filename-display.placeholder {
    color: #666;
    font-style: italic;
  }

  .controls-panel {
    background: #2a2a2a;
    border-radius: 8px;
    padding: 1.5rem;
    max-height: 800px;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
    align-self: start;
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
    color: #9c27b0;
  }

  h3 {
    margin: 0 0 0.5rem 0;
    color: #9c27b0;
  }

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
    background: #9c27b0;
    border-color: #9c27b0;
    color: #fff;
  }

  button:disabled {
    opacity: 0.4;
    cursor: not-allowed;
    background: #2a2a2a;
  }

  .key-color-controls {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
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
    color: #9c27b0;
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
    background: #9c27b0;
    cursor: pointer;
    border-radius: 50%;
  }

  input[type="range"]::-moz-range-thumb {
    width: 18px;
    height: 18px;
    background: #9c27b0;
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
    border-left: 4px solid #9c27b0;
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
