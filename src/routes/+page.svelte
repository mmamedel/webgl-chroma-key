<script lang="ts">
  import { onMount } from "svelte";
  import vertShader from "$lib/shaders/basic.vert?raw";
  import fragShader from "$lib/shaders/original.frag?raw";

  let canvas = $state<HTMLCanvasElement | null>(null);
  let video: HTMLVideoElement;
  let isPlaying = $state<boolean>(false);
  let currentTime = $state<number>(0);
  let duration = $state<number>(0);
  let seeking = $state<boolean>(false);

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
    source: HTMLImageElement | HTMLVideoElement
  ): WebGLTexture | null {
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);

    // Fill with placeholder
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

    if (source instanceof HTMLImageElement) {
      if (source.complete) {
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(
          gl.TEXTURE_2D,
          0,
          gl.RGBA,
          gl.RGBA,
          gl.UNSIGNED_BYTE,
          source
        );
      } else {
        source.onload = () => {
          gl.bindTexture(gl.TEXTURE_2D, texture);
          gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            source
          );
        };
      }
    }

    return texture;
  }

  function updateTexture(
    gl: WebGLRenderingContext,
    texture: WebGLTexture,
    video: HTMLVideoElement
  ): void {
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, video);
  }

  onMount(() => {
    if (!canvas) {
      throw new Error("Canvas element not found");
    }

    const gl = canvas.getContext("webgl");
    if (!gl) {
      throw new Error("WebGL not supported");
    }

    // Create shaders and program
    const vertexShader = createShader(gl, gl.VERTEX_SHADER, vertShader);
    const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fragShader);

    if (!vertexShader || !fragmentShader) {
      throw new Error("Failed to create shaders");
    }

    const program = createProgram(gl, vertexShader, fragmentShader);
    if (!program) {
      throw new Error("Failed to create program");
    }

    // Set up geometry (full-screen quad)
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

    // Get attribute and uniform locations
    const positionLocation = gl.getAttribLocation(program, "a_position");
    const texCoordLocation = gl.getAttribLocation(program, "a_texCoord");
    const videoLocation = gl.getUniformLocation(program, "u_video");
    const backgroundLocation = gl.getUniformLocation(program, "u_background");
    const resolutionLocation = gl.getUniformLocation(program, "u_resolution");

    // Load background image
    const backgroundImage = new Image();
    backgroundImage.src = "/blue.jpg";
    const backgroundTexture = setupTexture(gl, backgroundImage);

    // Create video texture
    const videoTexture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, videoTexture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    // Render loop
    function render() {
      if (!canvas || !program || !gl) return;

      if (video && video.readyState >= video.HAVE_CURRENT_DATA) {
        // Update canvas size to match video
        if (
          canvas.width !== video.videoWidth ||
          canvas.height !== video.videoHeight
        ) {
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
        }

        gl.viewport(0, 0, canvas.width, canvas.height);

        // Update video texture
        updateTexture(gl, videoTexture, video);

        // Clear and draw
        gl.clearColor(0, 0, 0, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.useProgram(program);

        // Set up position attribute
        gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
        gl.enableVertexAttribArray(positionLocation);
        gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

        // Set up texCoord attribute
        gl.bindBuffer(gl.ARRAY_BUFFER, texCoordBuffer);
        gl.enableVertexAttribArray(texCoordLocation);
        gl.vertexAttribPointer(texCoordLocation, 2, gl.FLOAT, false, 0, 0);

        // Set uniforms
        gl.uniform2f(resolutionLocation, canvas.width, canvas.height);

        // Bind textures
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, videoTexture);
        gl.uniform1i(videoLocation, 0);

        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, backgroundTexture);
        gl.uniform1i(backgroundLocation, 1);

        // Draw
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
</script>

<main>
  <div class="header">
    <h1>Chroma Key Demo - Original Shadertoy Shader</h1>
    <a href="/phase1" class="next-link">Phase 1: Core Parameters →</a>
  </div>
  <div class="container">
    <div class="video-container">
      <video
        bind:this={video}
        src="/060_INSIGHT-4_Paragraph_20251117_113546.mp4"
        loop
        muted
        crossorigin="anonymous"
        style="display: none;"
        onloadeddata={() => {
          if (video && canvas) {
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
          }
        }}
        ontimeupdate={handleTimeUpdate}
        onloadedmetadata={handleLoadedMetadata}
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
            style="width: {duration > 0 ? (currentTime / duration) * 100 : 0}%"
          ></div>
        </div>
        <span class="time">{formatTime(duration)}</span>
      </div>
    </div>

    <div class="info">
      <h2>Current Implementation</h2>
      <ul>
        <li>
          <strong>Key Color:</strong> Hardcoded green (0.157, 0.576, 0.129)
        </li>
        <li><strong>Weights:</strong> H=4, S=1, V=2 (fixed)</li>
        <li><strong>Threshold:</strong> 3.0 × dist - 1.5 (fixed)</li>
        <li>
          <strong>Spill Suppression:</strong> 50% saturation reduction (fixed)
        </li>
      </ul>
      <p>
        <em
          >See gap-analysis.md for what needs to be added for Ultra Key parity</em
        >
      </p>
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
    max-width: 1400px;
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
  }

  .next-link {
    color: #4caf50;
    text-decoration: none;
    font-weight: 600;
    padding: 0.5rem 1rem;
    border: 2px solid #4caf50;
    border-radius: 4px;
    transition: all 0.2s;
    white-space: nowrap;
  }

  .next-link:hover {
    background: #4caf50;
    color: #1a1a1a;
  }

  h2 {
    color: #4caf50;
    margin-top: 0;
  }

  .container {
    display: flex;
    flex-direction: column;
    gap: 2rem;
  }

  .video-container {
    display: flex;
    justify-content: center;
    background: #000;
    border-radius: 8px;
    overflow: hidden;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
  }

  canvas {
    max-width: 100%;
    height: auto;
    display: block;
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

  button {
    padding: 0.75rem 2rem;
    font-size: 1rem;
    font-weight: 600;
    background: #4caf50;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    transition: background 0.2s;
  }

  button:hover {
    background: #45a049;
  }

  button:active {
    transform: scale(0.98);
  }

  .info {
    background: #2a2a2a;
    padding: 1.5rem;
    border-radius: 8px;
    border-left: 4px solid #4caf50;
  }

  .info ul {
    margin: 1rem 0;
    padding-left: 1.5rem;
  }

  .info li {
    margin: 0.5rem 0;
  }

  .info p {
    margin: 1rem 0 0 0;
    color: #888;
    font-style: italic;
  }

  strong {
    color: #4caf50;
  }
</style>
