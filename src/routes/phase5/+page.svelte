<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import vertShader from "$lib/shaders/basic.vert?raw";
  import fragShader from "$lib/shaders/phase5.frag?raw";
  import passthroughFragShader from "$lib/shaders/passthrough.frag?raw";

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
  let choke = $state<number>(0.0); // -20 to 20, negative=expand, positive=shrink
  let soften = $state<number>(0.0); // 0-20, blur amount for edges

  // Video source
  let videoSrc = $state<string>("");
  let uploadedFileName = $state<string>("");

  // Color picker state
  let colorInput: HTMLInputElement;
  let isPickingFromVideo = $state<boolean>(false);

  // Function to render original frame (assigned in onMount)
  let renderOriginalFrame: (() => void) | null = null;

  // Render loop optimization
  let animationFrameId: number | null = null;
  let lastRenderedTime = -1;
  let shouldRender = true;

  // WebGL context and program
  let gl = $state<WebGLRenderingContext | null>(null);
  let program = $state<WebGLProgram | null>(null);
  let passthroughProgram = $state<WebGLProgram | null>(null); // Simple passthrough shader for color picking
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

    // Set picking mode for hint display and force one render with passthrough shader
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
      // Render once more to restore the keyed result
      shouldRender = true;
    }
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

    // Create simple passthrough shader for color picking
    const passthroughFragmentShader = createShader(
      gl,
      gl.FRAGMENT_SHADER,
      passthroughFragShader
    );
    if (!passthroughFragmentShader) {
      throw new Error("Failed to create passthrough fragment shader");
    }
    passthroughProgram = createProgram(
      gl,
      vertexShader,
      passthroughFragmentShader
    );
    if (!passthroughProgram) {
      throw new Error("Failed to create passthrough program");
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
      contrast: gl.getUniformLocation(program!, "u_contrast"),
      midPoint: gl.getUniformLocation(program!, "u_midPoint"),
      choke: gl.getUniformLocation(program!, "u_choke"),
      soften: gl.getUniformLocation(program!, "u_soften"),
    };

    // Load video texture
    const videoTexture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, videoTexture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    // Manually render a frame with original video (for color picking)
    renderOriginalFrame = () => {
      if (!gl || !program || !video || !canvas) return;

      if (video.readyState >= video.HAVE_CURRENT_DATA) {
        gl.viewport(0, 0, canvas.width, canvas.height);
        updateVideoTexture(gl, videoTexture, video);

        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.useProgram(program);

        gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
        gl.enableVertexAttribArray(positionLocation);
        gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

        gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
        gl.enableVertexAttribArray(texCoordLocation);
        gl.vertexAttribPointer(texCoordLocation, 2, gl.FLOAT, false, 0, 0);

        // Set all uniforms with transparency = 0 to show original
        gl.uniform2f(uniforms.resolution, canvas.width, canvas.height);
        gl.uniform3f(uniforms.keyColor, keyColor.r, keyColor.g, keyColor.b);
        gl.uniform1f(uniforms.transparency, 0); // Force 0 to show original
        gl.uniform1f(uniforms.tolerance, tolerance);
        gl.uniform1i(uniforms.outputMode, outputMode);
        gl.uniform1f(uniforms.highlight, highlight);
        gl.uniform1f(uniforms.shadow, shadow);
        gl.uniform1f(uniforms.pedestal, pedestal);
        gl.uniform1f(uniforms.spillSuppression, spillSuppression);
        gl.uniform1f(uniforms.contrast, contrast);
        gl.uniform1f(uniforms.midPoint, midPoint);
        gl.uniform1f(uniforms.choke, choke);
        gl.uniform1f(uniforms.soften, soften);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, videoTexture);
        gl.uniform1i(uniforms.video, 0);

        gl.drawArrays(gl.TRIANGLES, 0, 6);
      }
    };

    // Render loop with optimization
    function render() {
      if (!gl || !program) return;

      if (video && video.readyState >= video.HAVE_CURRENT_DATA) {
        // Check if we need to render
        const currentVideoTime = video.currentTime;
        const hasTimeChanged = currentVideoTime !== lastRenderedTime;
        const needsRender = !video.paused || hasTimeChanged || shouldRender;

        if (needsRender) {
          if (
            canvas.width !== video.videoWidth ||
            canvas.height !== video.videoHeight
          ) {
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
          }

          gl.viewport(0, 0, canvas.width, canvas.height);
          updateVideoTexture(gl, videoTexture, video);

          gl.clearColor(0, 0, 0, 0);
          gl.clear(gl.COLOR_BUFFER_BIT);

          // Use passthrough shader when picking colors, otherwise use chroma key shader
          const activeProgram = isPickingFromVideo
            ? passthroughProgram
            : program;
          gl.useProgram(activeProgram);

          // Set up attributes
          gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
          gl.enableVertexAttribArray(positionLocation);
          gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

          gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
          gl.enableVertexAttribArray(texCoordLocation);
          gl.vertexAttribPointer(texCoordLocation, 2, gl.FLOAT, false, 0, 0);

          // Bind video texture
          gl.activeTexture(gl.TEXTURE0);
          gl.bindTexture(gl.TEXTURE_2D, videoTexture);

          if (isPickingFromVideo && passthroughProgram) {
            // For passthrough shader, just set the video texture uniform
            const videoLoc = gl.getUniformLocation(
              passthroughProgram,
              "u_video"
            );
            gl.uniform1i(videoLoc, 0);
          } else {
            // Set all uniforms for chroma key shader
            gl.uniform2f(uniforms.resolution, canvas.width, canvas.height);
            gl.uniform3f(uniforms.keyColor, keyColor.r, keyColor.g, keyColor.b);
            gl.uniform1f(uniforms.transparency, transparency);
            gl.uniform1f(uniforms.tolerance, tolerance);
            gl.uniform1i(uniforms.outputMode, outputMode);
            gl.uniform1f(uniforms.highlight, highlight);
            gl.uniform1f(uniforms.shadow, shadow);
            gl.uniform1f(uniforms.pedestal, pedestal);
            gl.uniform1f(uniforms.spillSuppression, spillSuppression);
            gl.uniform1f(uniforms.contrast, contrast);
            gl.uniform1f(uniforms.midPoint, midPoint);
            gl.uniform1f(uniforms.choke, choke);
            gl.uniform1f(uniforms.soften, soften);
            gl.uniform1i(uniforms.video, 0);
          }

          gl.drawArrays(gl.TRIANGLES, 0, 6);

          lastRenderedTime = currentVideoTime;
          shouldRender = false;
        }
      }

      animationFrameId = requestAnimationFrame(render);
    }

    render();
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
  });

  function togglePlayPause(): void {
    if (!video || !videoSrc) return;
    if (video.paused) {
      video.play();
      isPlaying = true;
      shouldRender = true; // Resume rendering
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
    <h1>Phase 5: Matte Cleanup</h1>
    <div class="nav-links">
      <a href="/phase4" class="back-link">← Phase 4</a>
      <a href="/phase3" class="back-link">Phase 3</a>
      <a href="/phase2" class="back-link">Phase 2</a>
    </div>
  </div>

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
      <!-- <div class="section">
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
      </div> -->

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
            bind:value={keyColorHex}
            onchange={() => (currentPreset = "custom")}
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
            Removes green/blue color spill (color bleeding from background onto
            subject). 0 = no suppression, 50 = balanced, 100 = maximum removal.
            Desaturates and reduces the key color component.
          </p>
        </div>
      </div>

      <div class="section">
        <h2>Phase 5: Matte Cleanup</h2>

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
            Pushes semi-transparent pixels toward black or white. Range 0-200.
            Higher values create cleaner mattes by removing muddy mid-tones.
            Best viewed in Alpha Channel mode.
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
            Pivot point for contrast. Below 50 = favors transparency, Above 50 =
            favors opacity. Works with Contrast parameter.
          </p>
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
            aria-label="Choke"
          />
          <p class="help">
            Erode/dilate matte edges. Negative = expand (dilate), Positive =
            shrink (erode). Use to remove edge fringing or grow edges.
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
            aria-label="Soften"
          />
          <p class="help">
            Blur matte edges for smoother transitions. Higher values create more
            gradual falloff. Apply after Choke.
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
        <h3>✅ Phase 5: Matte Cleanup (Complete)</h3>
        <ul>
          <li>
            <strong>Contrast</strong> - Cleans up gray semi-transparent areas by
            pushing them toward full transparency or opacity
          </li>
          <li>
            <strong>Mid Point</strong> - Adjusts the pivot point for contrast calculations
            (50 = center)
          </li>
          <li>
            <strong>Choke</strong> - Erodes (positive) or dilates (negative) matte
            edges. Samples 3x3 or 5x5 neighborhood.
          </li>
          <li>
            <strong>Soften</strong> - Applies Gaussian blur to alpha channel for
            smoother edge transitions.
          </li>
        </ul>
        <p class="next">
          <strong>Status:</strong> Phase 5 complete with all 4 matte cleanup parameters!
          Choke and Soften use simplified single-pass implementation.
        </p>
        <p class="next">
          <strong>Tip:</strong> Best viewed in Alpha Channel mode. Try Aggressive
          preset to see all effects combined.
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
    color: #4caf50;
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
