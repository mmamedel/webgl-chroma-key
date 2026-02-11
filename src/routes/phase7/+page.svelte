<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import chromakeyShader from "$lib/shaders/phase7-chromakey.wgsl?raw";
  import chokeShader from "$lib/shaders/phase7-choke.wgsl?raw";
  import softenShader from "$lib/shaders/phase7-soften.wgsl?raw";
  import outputShader from "$lib/shaders/phase7-output.wgsl?raw";

  // State
  let canvas: HTMLCanvasElement;
  let video: HTMLVideoElement;
  let isPlaying = $state<boolean>(false);
  let currentTime = $state<number>(0);
  let duration = $state<number>(0);
  let seeking = $state<boolean>(false);
  let webgpuSupported = $state<boolean>(true);
  let errorMessage = $state<string>("");

  // Chroma Key Parameters
  let keyColor = $state<{ r: number; g: number; b: number }>({
    r: 0.157,
    g: 0.576,
    b: 0.129,
  });
  let keyColorHex = $state<string>("#28933d");
  let transparency = $state<number>(50.0);
  let tolerance = $state<number>(50.0);
  let outputMode = $state<number>(0);
  let currentPreset = $state<string>("default");

  // Matte Generation
  let highlight = $state<number>(50.0);
  let shadow = $state<number>(50.0);
  let pedestal = $state<number>(0.0);

  // Spill Suppression
  let spillSuppression = $state<number>(0.0);

  // Matte Cleanup (now fully supported!)
  let contrast = $state<number>(0.0);
  let midPoint = $state<number>(50.0);
  let choke = $state<number>(0.0);
  let soften = $state<number>(0.0);

  // Video source
  let videoSrc = $state<string>("");
  let uploadedFileName = $state<string>("");

  // Color picker
  let colorInput: HTMLInputElement;

  // Render loop
  let animationFrameId: number | null = null;

  // WebGPU resources
  let device: GPUDevice | null = null;
  let context: GPUCanvasContext | null = null;

  // Pipelines
  let chromakeyPipeline: GPURenderPipeline | null = null;
  let chokePipeline: GPURenderPipeline | null = null;
  let softenPipeline: GPURenderPipeline | null = null;
  let outputPipeline: GPURenderPipeline | null = null;

  // Samplers and textures
  let sampler: GPUSampler | null = null;
  let videoTexture: GPUTexture | null = null;
  let intermediateTexture1: GPUTexture | null = null;
  let intermediateTexture2: GPUTexture | null = null;

  // Uniform buffers
  let chromakeyUniformBuffer: GPUBuffer | null = null;
  let chokeUniformBuffer: GPUBuffer | null = null;
  let softenUniformBuffer: GPUBuffer | null = null;
  let outputUniformBuffer: GPUBuffer | null = null;

  // Track video dimensions for texture recreation
  let lastVideoWidth = 0;
  let lastVideoHeight = 0;

  const CHROMAKEY_UNIFORM_SIZE = 80;
  const CHOKE_UNIFORM_SIZE = 16;
  const SOFTEN_UNIFORM_SIZE = 16;
  const OUTPUT_UNIFORM_SIZE = 16;

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
      if (videoSrc && videoSrc.startsWith("blob:")) {
        URL.revokeObjectURL(videoSrc);
      }
      videoSrc = URL.createObjectURL(file);
      uploadedFileName = file.name;
      if (video) {
        video.load();
        isPlaying = false;
      }
    }
  }

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

  $effect(() => {
    if (keyColorHex) {
      keyColor = hexToRgb(keyColorHex);
    }
  });

  async function useEyeDropper() {
    if (!video || !videoSrc) return;
    if (!("EyeDropper" in window)) {
      alert("EyeDropper API is not supported in your browser.");
      return;
    }
    try {
      // @ts-ignore
      const eyeDropper = new EyeDropper();
      const result = await eyeDropper.open();
      keyColorHex = result.sRGBHex;
      currentPreset = "custom";
    } catch (e) {
      // User cancelled
    }
  }

  $effect(() => {
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
    if (video && video.paused) {
      // Trigger re-render
    }
  });

  async function initWebGPU() {
    if (!navigator.gpu) {
      webgpuSupported = false;
      errorMessage = "WebGPU is not supported in your browser.";
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

    // Create pipelines
    const chromakeyModule = device.createShaderModule({
      code: chromakeyShader,
    });
    const chokeModule = device.createShaderModule({ code: chokeShader });
    const softenModule = device.createShaderModule({ code: softenShader });
    const outputModule = device.createShaderModule({ code: outputShader });

    // Chromakey pipeline (renders to RGBA texture)
    chromakeyPipeline = device.createRenderPipeline({
      layout: "auto",
      vertex: { module: chromakeyModule, entryPoint: "vs" },
      fragment: {
        module: chromakeyModule,
        entryPoint: "fs",
        targets: [{ format: "rgba8unorm" }],
      },
      primitive: { topology: "triangle-list" },
    });

    // Choke pipeline
    chokePipeline = device.createRenderPipeline({
      layout: "auto",
      vertex: { module: chokeModule, entryPoint: "vs" },
      fragment: {
        module: chokeModule,
        entryPoint: "fs",
        targets: [{ format: "rgba8unorm" }],
      },
      primitive: { topology: "triangle-list" },
    });

    // Soften pipeline
    softenPipeline = device.createRenderPipeline({
      layout: "auto",
      vertex: { module: softenModule, entryPoint: "vs" },
      fragment: {
        module: softenModule,
        entryPoint: "fs",
        targets: [{ format: "rgba8unorm" }],
      },
      primitive: { topology: "triangle-list" },
    });

    // Output pipeline (renders to screen)
    outputPipeline = device.createRenderPipeline({
      layout: "auto",
      vertex: { module: outputModule, entryPoint: "vs" },
      fragment: {
        module: outputModule,
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
      primitive: { topology: "triangle-list" },
    });

    // Create sampler
    sampler = device.createSampler({
      magFilter: "linear",
      minFilter: "linear",
    });

    // Create uniform buffers
    chromakeyUniformBuffer = device.createBuffer({
      size: CHROMAKEY_UNIFORM_SIZE,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    chokeUniformBuffer = device.createBuffer({
      size: CHOKE_UNIFORM_SIZE,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    softenUniformBuffer = device.createBuffer({
      size: SOFTEN_UNIFORM_SIZE,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    outputUniformBuffer = device.createBuffer({
      size: OUTPUT_UNIFORM_SIZE,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    return true;
  }

  function createTexturesIfNeeded(width: number, height: number) {
    if (!device || (width === lastVideoWidth && height === lastVideoHeight))
      return;

    // Destroy old textures
    videoTexture?.destroy();
    intermediateTexture1?.destroy();
    intermediateTexture2?.destroy();

    // Video texture (copy target)
    videoTexture = device.createTexture({
      size: [width, height],
      format: "rgba8unorm",
      usage:
        GPUTextureUsage.TEXTURE_BINDING |
        GPUTextureUsage.COPY_DST |
        GPUTextureUsage.RENDER_ATTACHMENT,
    });

    // Intermediate textures for ping-pong rendering
    intermediateTexture1 = device.createTexture({
      size: [width, height],
      format: "rgba8unorm",
      usage:
        GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT,
    });

    intermediateTexture2 = device.createTexture({
      size: [width, height],
      format: "rgba8unorm",
      usage:
        GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT,
    });

    lastVideoWidth = width;
    lastVideoHeight = height;
  }

  function updateUniforms() {
    if (!device) return;

    // Chromakey uniforms
    const chromakeyData = new ArrayBuffer(CHROMAKEY_UNIFORM_SIZE);
    const chromakeyFloats = new Float32Array(chromakeyData);
    const chromakeyInts = new Int32Array(chromakeyData);

    chromakeyFloats[0] = canvas.width;
    chromakeyFloats[1] = canvas.height;
    chromakeyFloats[4] = keyColor.r;
    chromakeyFloats[5] = keyColor.g;
    chromakeyFloats[6] = keyColor.b;
    chromakeyFloats[7] = transparency;
    chromakeyFloats[8] = tolerance;
    chromakeyFloats[9] = highlight;
    chromakeyFloats[10] = shadow;
    chromakeyFloats[11] = pedestal;
    chromakeyFloats[12] = spillSuppression;
    chromakeyFloats[13] = contrast;
    chromakeyFloats[14] = midPoint;
    chromakeyFloats[15] = choke;
    chromakeyFloats[16] = soften;
    chromakeyInts[17] = outputMode;

    device.queue.writeBuffer(chromakeyUniformBuffer!, 0, chromakeyData);

    // Choke uniforms
    const chokeData = new Float32Array([canvas.width, canvas.height, choke, 0]);
    device.queue.writeBuffer(chokeUniformBuffer!, 0, chokeData);

    // Soften uniforms
    const softenData = new Float32Array([
      canvas.width,
      canvas.height,
      soften,
      0,
    ]);
    device.queue.writeBuffer(softenUniformBuffer!, 0, softenData);

    // Output uniforms
    const outputData = new Int32Array([outputMode, 0, 0, 0]);
    device.queue.writeBuffer(outputUniformBuffer!, 0, outputData);
  }

  function render() {
    if (
      !device ||
      !context ||
      !video ||
      !chromakeyPipeline ||
      !chokePipeline ||
      !softenPipeline ||
      !outputPipeline ||
      !sampler
    ) {
      animationFrameId = requestAnimationFrame(render);
      return;
    }

    const canRender =
      video.readyState >= video.HAVE_CURRENT_DATA &&
      video.videoWidth > 0 &&
      video.videoHeight > 0 &&
      (!video.paused || video.currentTime > 0);

    if (canRender) {
      try {
        // Update canvas size
        if (
          canvas.width !== video.videoWidth ||
          canvas.height !== video.videoHeight
        ) {
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
        }

        // Create/recreate textures if needed
        createTexturesIfNeeded(video.videoWidth, video.videoHeight);

        if (!videoTexture || !intermediateTexture1 || !intermediateTexture2) {
          animationFrameId = requestAnimationFrame(render);
          return;
        }

        // Copy video frame to texture
        device.queue.copyExternalImageToTexture(
          { source: video, flipY: true },
          { texture: videoTexture },
          [video.videoWidth, video.videoHeight]
        );

        updateUniforms();

        const commandEncoder = device.createCommandEncoder();

        // Pass 1: Chromakey (video -> intermediate1)
        const chromakeyBindGroup = device.createBindGroup({
          layout: chromakeyPipeline.getBindGroupLayout(0),
          entries: [
            { binding: 0, resource: sampler },
            { binding: 1, resource: videoTexture.createView() },
            { binding: 2, resource: { buffer: chromakeyUniformBuffer! } },
          ],
        });

        const pass1 = commandEncoder.beginRenderPass({
          colorAttachments: [
            {
              view: intermediateTexture1.createView(),
              clearValue: { r: 0, g: 0, b: 0, a: 0 },
              loadOp: "clear",
              storeOp: "store",
            },
          ],
        });
        pass1.setPipeline(chromakeyPipeline);
        pass1.setBindGroup(0, chromakeyBindGroup);
        pass1.draw(6);
        pass1.end();

        // Pass 2: Choke (intermediate1 -> intermediate2)
        const chokeBindGroup = device.createBindGroup({
          layout: chokePipeline.getBindGroupLayout(0),
          entries: [
            { binding: 0, resource: sampler },
            { binding: 1, resource: intermediateTexture1.createView() },
            { binding: 2, resource: { buffer: chokeUniformBuffer! } },
          ],
        });

        const pass2 = commandEncoder.beginRenderPass({
          colorAttachments: [
            {
              view: intermediateTexture2.createView(),
              clearValue: { r: 0, g: 0, b: 0, a: 0 },
              loadOp: "clear",
              storeOp: "store",
            },
          ],
        });
        pass2.setPipeline(chokePipeline);
        pass2.setBindGroup(0, chokeBindGroup);
        pass2.draw(6);
        pass2.end();

        // Pass 3: Soften (intermediate2 -> intermediate1)
        const softenBindGroup = device.createBindGroup({
          layout: softenPipeline.getBindGroupLayout(0),
          entries: [
            { binding: 0, resource: sampler },
            { binding: 1, resource: intermediateTexture2.createView() },
            { binding: 2, resource: { buffer: softenUniformBuffer! } },
          ],
        });

        const pass3 = commandEncoder.beginRenderPass({
          colorAttachments: [
            {
              view: intermediateTexture1.createView(),
              clearValue: { r: 0, g: 0, b: 0, a: 0 },
              loadOp: "clear",
              storeOp: "store",
            },
          ],
        });
        pass3.setPipeline(softenPipeline);
        pass3.setBindGroup(0, softenBindGroup);
        pass3.draw(6);
        pass3.end();

        // Pass 4: Output (intermediate1 -> screen)
        const outputBindGroup = device.createBindGroup({
          layout: outputPipeline.getBindGroupLayout(0),
          entries: [
            { binding: 0, resource: sampler },
            { binding: 1, resource: intermediateTexture1.createView() },
            { binding: 2, resource: { buffer: outputUniformBuffer! } },
          ],
        });

        const pass4 = commandEncoder.beginRenderPass({
          colorAttachments: [
            {
              view: context.getCurrentTexture().createView(),
              clearValue: { r: 0, g: 0, b: 0, a: 0 },
              loadOp: "clear",
              storeOp: "store",
            },
          ],
        });
        pass4.setPipeline(outputPipeline);
        pass4.setBindGroup(0, outputBindGroup);
        pass4.draw(6);
        pass4.end();

        device.queue.submit([commandEncoder.finish()]);
      } catch (e) {
        console.debug("Render error:", e);
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
    if (animationFrameId !== null) {
      cancelAnimationFrame(animationFrameId);
    }
    if (videoSrc && videoSrc.startsWith("blob:")) {
      URL.revokeObjectURL(videoSrc);
    }
    videoTexture?.destroy();
    intermediateTexture1?.destroy();
    intermediateTexture2?.destroy();
    chromakeyUniformBuffer?.destroy();
    chokeUniformBuffer?.destroy();
    softenUniformBuffer?.destroy();
    outputUniformBuffer?.destroy();
  });

  function togglePlayPause(): void {
    if (!video || !videoSrc) return;
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
    <h1>Phase 7: Multi-Pass WebGPU</h1>
    <div class="nav-links">
      <a href="/phase6" class="back-link">← Phase 6</a>
      <a href="/phase5" class="back-link">Phase 5 (WebGL)</a>
    </div>
  </div>

  {#if !webgpuSupported}
    <div class="error-banner">
      <h2>WebGPU Not Available</h2>
      <p>{errorMessage}</p>
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
              onclick={handleSeek}
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
                  role="button"
                  tabindex="0"
                ></div>
                <button
                  class="eyedropper-btn"
                  onclick={useEyeDropper}
                  disabled={!videoSrc}>💧</button
                >
              </div>
              <div class="color-info">
                <input
                  type="text"
                  class="hex-input"
                  bind:value={keyColorHex}
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
            />
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
            />
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
            />
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
            />
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
            />
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
            />
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
            />
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
            />
          </div>
          <div class="control">
            <div class="control-label">
              <span class="label-text">Choke</span>
              <span class="value">{choke.toFixed(1)}</span>
            </div>
            <input
              type="range"
              bind:value={choke}
              min="-20"
              max="20"
              step="0.1"
            />
            <p class="help">
              Erode (positive) or dilate (negative) matte edges
            </p>
          </div>
          <div class="control">
            <div class="control-label">
              <span class="label-text">Soften</span>
              <span class="value">{soften.toFixed(1)}</span>
            </div>
            <input
              type="range"
              bind:value={soften}
              min="0"
              max="20"
              step="0.1"
            />
            <p class="help">Blur matte edges for smoother transitions</p>
          </div>
        </div>

        <div class="section">
          <h2>Output Mode</h2>
          <div class="output-buttons">
            <button
              class:active={outputMode === 0}
              onclick={() => (outputMode = 0)}>Composite</button
            >
            <button
              class:active={outputMode === 1}
              onclick={() => (outputMode = 1)}>Alpha</button
            >
            <button
              class:active={outputMode === 2}
              onclick={() => (outputMode = 2)}>Status</button
            >
          </div>
        </div>

        <div class="section">
          <button class="reset-button" onclick={resetToDefaults}
            >Reset to Defaults</button
          >
        </div>

        <div class="info-box">
          <h3>🚀 Phase 7: Multi-Pass WebGPU</h3>
          <ul>
            <li>
              <strong>4 render passes</strong> - Chromakey → Choke → Soften → Output
            </li>
            <li>
              <strong>copyExternalImageToTexture</strong> - Video to GPU texture
            </li>
            <li>
              <strong>Full feature support</strong> - Choke and Soften now work!
            </li>
          </ul>
          <p class="next">
            <strong>Trade-off:</strong> Uses more GPU memory (3 textures) but enables
            neighbor sampling for edge effects.
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
    color: #ff5722;
    font-size: 2rem;
  }

  .nav-links {
    display: flex;
    gap: 1rem;
  }

  .back-link {
    color: #ff5722;
    text-decoration: none;
    font-weight: 600;
    padding: 0.5rem 1rem;
    border: 2px solid #ff5722;
    border-radius: 4px;
    transition: all 0.2s;
  }

  .back-link:hover {
    background: #ff5722;
    color: #1a1a1a;
  }

  .error-banner {
    background: #d32f2f;
    padding: 2rem;
    border-radius: 8px;
    text-align: center;
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
  }

  .eyedropper-btn {
    width: 32px;
    height: 40px;
    background: #3a3a3a;
    border: 1px solid #4a4a4a;
    border-radius: 2px;
    cursor: pointer;
    font-size: 16px;
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
    color: #ccc;
    font-family: monospace;
    font-size: 13px;
    width: 90px;
  }

  .rgb-values {
    display: flex;
    gap: 0.5rem;
    font-family: monospace;
    font-size: 11px;
    color: #888;
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
    overflow: hidden;
  }

  .timeline-progress {
    height: 100%;
    background: #ff5722;
    border-radius: 4px;
  }

  .time {
    font-size: 0.9rem;
    color: #ccc;
    min-width: 45px;
    text-align: center;
  }

  .control-buttons {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .load-video-btn {
    padding: 0.75rem 1rem;
    font-size: 0.9rem;
    font-weight: 600;
    background: #3a3a3a;
    color: white;
    border-radius: 4px;
    cursor: pointer;
  }

  .filename-display {
    color: #ff5722;
    font-size: 0.9rem;
    font-weight: 500;
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
    color: #ff5722;
  }

  h3 {
    margin: 0 0 0.5rem 0;
    color: #ff5722;
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
  }

  button:hover:not(:disabled) {
    background: #4a4a4a;
  }

  button.active {
    background: #ff5722;
    border-color: #ff5722;
  }

  button:disabled {
    opacity: 0.4;
    cursor: not-allowed;
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
    color: #ff5722;
    font-family: monospace;
  }

  input[type="range"] {
    width: 100%;
    height: 6px;
    background: #3a3a3a;
    border-radius: 3px;
    -webkit-appearance: none;
  }

  input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 18px;
    height: 18px;
    background: #ff5722;
    cursor: pointer;
    border-radius: 50%;
  }

  .help {
    margin: 0.5rem 0 0 0;
    font-size: 0.85rem;
    color: #888;
  }

  .reset-button {
    width: 100%;
    background: #d32f2f;
  }

  .info-box {
    background: #1e1e1e;
    padding: 1rem;
    border-radius: 4px;
    border-left: 4px solid #ff5722;
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
  }
</style>
