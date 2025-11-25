#!/usr/bin/env python3
"""
Chroma Key Video Processor - Phase 5
Uses PyOpenGL to process video with WebGL shaders
Supports: Transparency, Tolerance, Highlight, Shadow, Pedestal, Spill Suppression, Contrast, Mid Point, Choke, Soften
"""

import sys
import cv2
import numpy as np
from pathlib import Path
from OpenGL.GL import *
from OpenGL.GL import shaders
import glfw
import subprocess
import shutil
import time


class ChromaKeyProcessor:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.window = None
        self.program = None
        self.vao = None
        self.textures = {}
        self.uniforms = {}
        
    def init_gl(self):
        """Initialize OpenGL context with GLFW"""
        if not glfw.init():
            raise Exception("Failed to initialize GLFW")
        
        # Create hidden window for offscreen rendering
        glfw.window_hint(glfw.VISIBLE, glfw.FALSE)
        glfw.window_hint(glfw.CONTEXT_VERSION_MAJOR, 3)
        glfw.window_hint(glfw.CONTEXT_VERSION_MINOR, 3)
        glfw.window_hint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
        glfw.window_hint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
        
        self.window = glfw.create_window(self.width, self.height, "Offscreen", None, None)
        if not self.window:
            glfw.terminate()
            raise Exception("Failed to create GLFW window")
        
        glfw.make_context_current(self.window)
        
        # Enable blending for transparency
        glEnable(GL_BLEND)
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        
        print(f"OpenGL Version: {glGetString(GL_VERSION).decode()}")
        print(f"GLSL Version: {glGetString(GL_SHADING_LANGUAGE_VERSION).decode()}")
        
    def load_shaders(self, vert_path, frag_path):
        """Load and compile shaders"""
        with open(vert_path, 'r') as f:
            vert_source = f.read()
        
        with open(frag_path, 'r') as f:
            frag_source = f.read()
        
        # Convert GLSL ES to GLSL 3.3
        vert_source = self._convert_vertex_shader(vert_source)
        frag_source = self._convert_fragment_shader(frag_source)
        
        try:
            vertex_shader = shaders.compileShader(vert_source, GL_VERTEX_SHADER)
            fragment_shader = shaders.compileShader(frag_source, GL_FRAGMENT_SHADER)
            
            # Manually link program without validation (VAO binding issue on macOS)
            self.program = glCreateProgram()
            glAttachShader(self.program, vertex_shader)
            glAttachShader(self.program, fragment_shader)
            glLinkProgram(self.program)
            
            # Check link status
            if not glGetProgramiv(self.program, GL_LINK_STATUS):
                error = glGetProgramInfoLog(self.program).decode()
                raise RuntimeError(f"Program link error: {error}")
            
            # Clean up shaders (they're now in the program)
            glDeleteShader(vertex_shader)
            glDeleteShader(fragment_shader)
            
        except Exception as e:
            print("Shader compilation error:", e)
            raise
        
        # Get uniform locations
        glUseProgram(self.program)
        self.uniforms = {
            'u_video': glGetUniformLocation(self.program, 'u_video'),
            'u_resolution': glGetUniformLocation(self.program, 'u_resolution'),
            'u_keyColor': glGetUniformLocation(self.program, 'u_keyColor'),
            'u_transparency': glGetUniformLocation(self.program, 'u_transparency'),
            'u_tolerance': glGetUniformLocation(self.program, 'u_tolerance'),
            'u_highlight': glGetUniformLocation(self.program, 'u_highlight'),
            'u_shadow': glGetUniformLocation(self.program, 'u_shadow'),
            'u_pedestal': glGetUniformLocation(self.program, 'u_pedestal'),
            'u_spillSuppression': glGetUniformLocation(self.program, 'u_spillSuppression'),
            'u_contrast': glGetUniformLocation(self.program, 'u_contrast'),
            'u_midPoint': glGetUniformLocation(self.program, 'u_midPoint'),
            'u_choke': glGetUniformLocation(self.program, 'u_choke'),
            'u_soften': glGetUniformLocation(self.program, 'u_soften'),
            'u_outputMode': glGetUniformLocation(self.program, 'u_outputMode'),
        }
        
    def _convert_vertex_shader(self, source):
        """Convert GLSL ES to GLSL 3.3"""
        source = source.replace('attribute', 'in')
        source = source.replace('varying', 'out')
        return '#version 330 core\n' + source
    
    def _convert_fragment_shader(self, source):
        """Convert GLSL ES to GLSL 3.3"""
        source = source.replace('varying', 'in')
        source = source.replace('texture2D', 'texture')
        source = source.replace('gl_FragColor', 'fragColor')
        
        # Add output declaration
        if 'out vec4 fragColor' not in source:
            lines = source.split('\n')
            # Find where to insert (after precision and uniforms)
            insert_idx = 0
            for i, line in enumerate(lines):
                if line.strip().startswith('precision'):
                    insert_idx = i + 1
                elif line.strip().startswith('uniform'):
                    insert_idx = i + 1
            lines.insert(insert_idx, '\nout vec4 fragColor;\n')
            source = '\n'.join(lines)
        
        return '#version 330 core\n' + source
    
    def setup_geometry(self):
        """Setup full-screen quad"""
        vertices = np.array([
            # positions   # texCoords
            -1.0, -1.0,   0.0, 1.0,
             1.0, -1.0,   1.0, 1.0,
            -1.0,  1.0,   0.0, 0.0,
            
            -1.0,  1.0,   0.0, 0.0,
             1.0, -1.0,   1.0, 1.0,
             1.0,  1.0,   1.0, 0.0,
        ], dtype=np.float32)
        
        self.vao = glGenVertexArrays(1)
        vbo = glGenBuffers(1)
        
        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, vbo)
        glBufferData(GL_ARRAY_BUFFER, vertices.nbytes, vertices, GL_STATIC_DRAW)
        
        # Position attribute
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, ctypes.c_void_p(0))
        
        # TexCoord attribute
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, ctypes.c_void_p(8))
        
        glBindVertexArray(0)
    
    def create_texture(self, name):
        """Create OpenGL texture"""
        texture = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, texture)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        self.textures[name] = texture
        return texture
    
    def load_background(self, bg_path):
        """Load background image"""
        bg = cv2.imread(bg_path)
        if bg is None:
            raise Exception(f"Failed to load background: {bg_path}")
        
        bg = cv2.cvtColor(bg, cv2.COLOR_BGR2RGBA)
        bg = cv2.resize(bg, (self.width, self.height))
        
        texture = self.create_texture('background')
        glBindTexture(GL_TEXTURE_2D, texture)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, self.width, self.height, 
                     0, GL_RGBA, GL_UNSIGNED_BYTE, bg)
    
    def update_video_texture(self, frame):
        """Update video texture with new frame"""
        if 'video' not in self.textures:
            self.create_texture('video')
        
        # Convert BGR to RGBA
        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGBA)
        
        glBindTexture(GL_TEXTURE_2D, self.textures['video'])
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, self.width, self.height,
                     0, GL_RGBA, GL_UNSIGNED_BYTE, frame)
    
    def render_frame(self, key_color, transparency, tolerance, 
                     highlight=50.0, shadow=50.0, pedestal=0.0, 
                     spill_suppression=30.0, contrast=0.0, mid_point=50.0,
                     choke=0.0, soften=0.0, output_mode=0):
        """Render a frame with current parameters"""
        # Clear with transparency (alpha = 0)
        glClearColor(0.0, 0.0, 0.0, 0.0)
        glClear(GL_COLOR_BUFFER_BIT)
        glUseProgram(self.program)
        
        # Set uniforms
        glUniform2f(self.uniforms['u_resolution'], self.width, self.height)
        glUniform3f(self.uniforms['u_keyColor'], key_color[0], key_color[1], key_color[2])
        glUniform1f(self.uniforms['u_transparency'], transparency)
        glUniform1f(self.uniforms['u_tolerance'], tolerance)
        glUniform1f(self.uniforms['u_highlight'], highlight)
        glUniform1f(self.uniforms['u_shadow'], shadow)
        glUniform1f(self.uniforms['u_pedestal'], pedestal)
        glUniform1f(self.uniforms['u_spillSuppression'], spill_suppression)
        glUniform1f(self.uniforms['u_contrast'], contrast)
        glUniform1f(self.uniforms['u_midPoint'], mid_point)
        glUniform1f(self.uniforms['u_choke'], choke)
        glUniform1f(self.uniforms['u_soften'], soften)
        glUniform1i(self.uniforms['u_outputMode'], output_mode)
        
        # Bind video texture
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, self.textures['video'])
        glUniform1i(self.uniforms['u_video'], 0)
        
        # Draw
        glBindVertexArray(self.vao)
        glDrawArrays(GL_TRIANGLES, 0, 6)
        glBindVertexArray(0)
        
        # Read pixels with alpha channel
        pixels = glReadPixels(0, 0, self.width, self.height, GL_RGBA, GL_UNSIGNED_BYTE)
        image = np.frombuffer(pixels, dtype=np.uint8).reshape(self.height, self.width, 4)
        
        # Flip vertically (OpenGL coordinates)
        image = np.flipud(image)
        
        # Keep RGBA for transparency
        return image
    
    def cleanup(self):
        """Cleanup OpenGL resources"""
        if self.vao:
            glDeleteVertexArrays(1, [self.vao])
        for texture in self.textures.values():
            glDeleteTextures(1, [texture])
        if self.program:
            glDeleteProgram(self.program)
        if self.window:
            glfw.destroy_window(self.window)
        glfw.terminate()


def process_video(input_path, output_path, 
                  key_color=(0.157, 0.576, 0.129),
                  transparency=50.0,
                  tolerance=50.0,
                  highlight=50.0,
                  shadow=50.0,
                  pedestal=0.0,
                  spill_suppression=30.0,
                  contrast=0.0,
                  mid_point=50.0,
                  choke=0.0,
                  soften=0.0,
                  output_mode=0,
                  keep_frames=False):
    """
    Process video with chroma key (Phase 5) - Outputs ProRes 4444 with transparency
    
    Args:
        input_path: Input video file
        output_path: Output video file (should end in .mov for ProRes)
        key_color: RGB tuple (0-1 range), default is green
        transparency: 0-100, controls keying threshold
        tolerance: 0-100, controls color range
        highlight: 0-100, controls bright area transparency
        shadow: 0-100, controls dark area transparency
        pedestal: 0-100, shifts entire alpha range
        spill_suppression: 0-100, removes color spill
        contrast: 0-200, pushes mid-tones toward black/white
        mid_point: 0-100, pivot point for contrast
        choke: -20 to 20, negative=expand, positive=shrink matte
        soften: 0-20, blur amount for edges
        output_mode: 0=Composite (with transparency), 1=Alpha Channel, 2=Status
        keep_frames: If True, preserve PNG frames for inspection
    """
    
    # Start performance tracking
    perf_start = time.time()
    perf_stats = {
        'init_time': 0,
        'frame_times': [],
        'ffmpeg_time': 0,
        'total_frames': 0
    }
    
    print("=" * 60)
    print("CHROMA KEY VIDEO PROCESSOR - PERFORMANCE TRACKING")
    print("=" * 60)
    print(f"Processing: {input_path}")
    print(f"Output: {output_path} (ProRes 4444 with Alpha)")
    print(f"Key Color: RGB{key_color}")
    print(f"Transparency: {transparency}, Tolerance: {tolerance}")
    print(f"Highlight: {highlight}, Shadow: {shadow}, Pedestal: {pedestal}")
    print(f"Spill Suppression: {spill_suppression}")
    print(f"Contrast: {contrast}, Mid Point: {mid_point}")
    print(f"Choke: {choke}, Soften: {soften}")
    output_mode_names = {0: 'Composite + Alpha', 1: 'Alpha Channel', 2: 'Status'}
    print(f"Output Mode: {output_mode_names.get(output_mode, 'Unknown')}")
    
    # Open input video
    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        raise Exception(f"Failed to open video: {input_path}")
    
    # Get video properties
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    print(f"Video: {width}x{height} @ {fps}fps, {total_frames} frames")
    
    # Initialize processor
    init_start = time.time()
    processor = ChromaKeyProcessor(width, height)
    processor.init_gl()
    
    # Setup geometry BEFORE loading shaders (VAO must exist for validation)
    processor.setup_geometry()
    
    # Load shaders - check if running in Docker (/app) or locally (video-processor/)
    script_dir = Path(__file__).parent
    if (script_dir / 'src' / 'lib' / 'shaders').exists():
        # Running in Docker container
        shader_dir = script_dir / 'src' / 'lib' / 'shaders'
    else:
        # Running locally from video-processor directory
        shader_dir = script_dir.parent / 'src' / 'lib' / 'shaders'
    
    processor.load_shaders(
        shader_dir / 'basic.vert',
        shader_dir / 'phase5.frag'
    )
    
    perf_stats['init_time'] = time.time() - init_start
    print(f"⚡ Initialization time: {perf_stats['init_time']:.2f}s")
    
    # Create temporary directory for PNG frames
    import tempfile
    temp_dir = Path(tempfile.mkdtemp(prefix='chroma_key_'))
    print(f"Temporary frame directory: {temp_dir}")
    
    print("\nProcessing frames...")
    frame_count = 0
    frame_processing_start = time.time()
    
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            frame_start = time.time()
            
            # Update texture and render
            processor.update_video_texture(frame)
            output_frame = processor.render_frame(
                key_color, transparency, tolerance,
                highlight, shadow, pedestal, spill_suppression,
                contrast, mid_point, choke, soften,
                output_mode
            )
            
            # Write frame as PNG with alpha channel
            # Convert RGBA to BGRA for OpenCV (cv2.imwrite expects BGRA for PNG with alpha)
            output_bgra = cv2.cvtColor(output_frame, cv2.COLOR_RGBA2BGRA)
            frame_path = temp_dir / f"frame_{frame_count:06d}.png"
            cv2.imwrite(str(frame_path), output_bgra, [cv2.IMWRITE_PNG_COMPRESSION, 0])
            
            frame_time = time.time() - frame_start
            perf_stats['frame_times'].append(frame_time)
            
            # Debug: Check first frame has alpha
            if frame_count == 0:
                print(f"First frame shape: {output_frame.shape}, dtype: {output_frame.dtype}")
                print(f"Alpha channel range: min={output_frame[:,:,3].min()}, max={output_frame[:,:,3].max()}")
            
            frame_count += 1
            if frame_count % 30 == 0:
                progress = (frame_count / total_frames) * 100
                avg_fps = frame_count / (time.time() - frame_processing_start)
                print(f"Progress: {frame_count}/{total_frames} ({progress:.1f}%) | FPS: {avg_fps:.2f}")
        
        perf_stats['total_frames'] = frame_count
        frame_processing_time = time.time() - frame_processing_start
        avg_frame_time = sum(perf_stats['frame_times']) / len(perf_stats['frame_times'])
        avg_fps = frame_count / frame_processing_time
        
        print(f"\n✅ Processed {frame_count} frames")
        print(f"⚡ Frame processing time: {frame_processing_time:.2f}s")
        print(f"⚡ Average FPS: {avg_fps:.2f}")
        print(f"⚡ Average time per frame: {avg_frame_time*1000:.2f}ms")
        
        # Test: Save a sample PNG to output for inspection
        sample_frame_path = Path(output_path).parent / "sample_frame_with_alpha.png"
        import shutil as sh
        if (temp_dir / "frame_000100.png").exists():
            sh.copy(temp_dir / "frame_000100.png", sample_frame_path)
            print(f"Sample PNG saved to: {sample_frame_path}")
            print("You can inspect this PNG file to verify it has transparency")
        
        print(f"\nConverting to ProRes 4444 with alpha...")
        ffmpeg_start = time.time()
        
        # Convert PNG sequence to ProRes 4444 using FFmpeg
        # Profile 4 = ProRes 4444 (supports alpha)
        ffmpeg_cmd = [
            'ffmpeg',
            '-y',  # Overwrite output file
            '-framerate', str(fps),
            '-i', str(temp_dir / 'frame_%06d.png'),
            '-c:v', 'prores_ks',  # ProRes encoder
            '-profile:v', '4',  # Profile 4 = ProRes 4444 (WITH alpha support)
            '-pix_fmt', 'yuva444p10le',  # 10-bit YUV with alpha
            '-vendor', 'apl0',  # Apple vendor code for compatibility
            str(output_path)
        ]
        
        # Run FFmpeg with direct output (no buffering to avoid hang on large videos)
        result = subprocess.run(ffmpeg_cmd)
        
        perf_stats['ffmpeg_time'] = time.time() - ffmpeg_start
        
        if result.returncode != 0:
            print(f"\nFFmpeg failed with return code {result.returncode}")
            raise Exception("Failed to create ProRes video")
        
        print("\n✅ FFmpeg conversion complete!")
        print(f"⚡ FFmpeg encoding time: {perf_stats['ffmpeg_time']:.2f}s")
        
        # Verify the output file has alpha channel using ffprobe
        print("\nVerifying alpha channel in output file...")
        probe_cmd = [
            'ffprobe',
            '-v', 'error',
            '-select_streams', 'v:0',
            '-show_entries', 'stream=pix_fmt,codec_name,width,height',
            '-of', 'default=noprint_wrappers=1',
            str(output_path)
        ]
        probe_result = subprocess.run(probe_cmd, capture_output=True, text=True)
        print(f"Video file info:\n{probe_result.stdout}")
        
        if 'yuva' in probe_result.stdout:
            print("✅ Alpha channel detected in output file!")
        else:
            print("⚠️  WARNING: Alpha channel NOT detected in output file!")
            print("The file may not have transparency encoded properly.")
        
        # Print final performance summary
        total_time = time.time() - perf_start
        
        print("\n" + "=" * 60)
        print("PERFORMANCE SUMMARY")
        print("=" * 60)
        print(f"Total processing time:     {total_time:.2f}s ({total_time/60:.2f}m)")
        print(f"  - Initialization:        {perf_stats['init_time']:.2f}s ({perf_stats['init_time']/total_time*100:.1f}%)")
        print(f"  - Frame processing:      {frame_processing_time:.2f}s ({frame_processing_time/total_time*100:.1f}%)")
        print(f"  - FFmpeg encoding:       {perf_stats['ffmpeg_time']:.2f}s ({perf_stats['ffmpeg_time']/total_time*100:.1f}%)")
        print(f"\nFrame statistics:")
        print(f"  - Total frames:          {perf_stats['total_frames']}")
        print(f"  - Average FPS:           {avg_fps:.2f}")
        print(f"  - Avg time per frame:    {avg_frame_time*1000:.2f}ms")
        print(f"  - Min frame time:        {min(perf_stats['frame_times'])*1000:.2f}ms")
        print(f"  - Max frame time:        {max(perf_stats['frame_times'])*1000:.2f}ms")
        print(f"\nThroughput:                {perf_stats['total_frames']/total_time:.2f} fps (end-to-end)")
        print("=" * 60)
        
        print(f"\n✅ Done! Output saved to: {output_path}")
    
    finally:
        cap.release()
        processor.cleanup()
        
        # Clean up temporary PNG frames (unless user wants to keep them)
        if keep_frames:
            frames_dir = Path(output_path).parent / "frames"
            shutil.move(str(temp_dir), str(frames_dir))
            print(f"\n📁 PNG frames preserved in: {frames_dir}")
            print("   You can inspect these to verify alpha channel exists")
        else:
            print("\nCleaning up temporary files...")
            shutil.rmtree(temp_dir)
            print("Cleanup complete!")


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Chroma Key Video Processor')
    parser.add_argument('--input', '-i', required=True, help='Input video file')
    parser.add_argument('--output', '-o', required=True, help='Output video file (.mov for ProRes)')
    parser.add_argument('--key-color', nargs=3, type=float, default=[0.157, 0.576, 0.129],
                        help='Key color RGB (0-1 range), default: green')
    parser.add_argument('--transparency', '-t', type=float, default=50.0,
                        help='Transparency parameter (0-100), default: 50')
    parser.add_argument('--tolerance', type=float, default=50.0,
                        help='Tolerance parameter (0-100), default: 50')
    parser.add_argument('--highlight', type=float, default=50.0,
                        help='Highlight parameter (0-100), default: 50')
    parser.add_argument('--shadow', type=float, default=50.0,
                        help='Shadow parameter (0-100), default: 50')
    parser.add_argument('--pedestal', type=float, default=0.0,
                        help='Pedestal parameter (0-100), default: 0')
    parser.add_argument('--spill-suppression', type=float, default=30.0,
                        help='Spill suppression (0-100), default: 30')
    parser.add_argument('--contrast', type=float, default=0.0,
                        help='Contrast (0-200), pushes mid-tones, default: 0')
    parser.add_argument('--mid-point', type=float, default=50.0,
                        help='Mid point (0-100), pivot for contrast, default: 50')
    parser.add_argument('--choke', type=float, default=0.0,
                        help='Choke (-20 to 20), negative=expand, positive=shrink, default: 0')
    parser.add_argument('--soften', type=float, default=0.0,
                        help='Soften (0-20), blur amount for edges, default: 0')
    parser.add_argument('--output-mode', type=int, choices=[0, 1, 2], default=0,
                        help='Output mode: 0=Composite, 1=Alpha Channel, 2=Status, default: 0')
    parser.add_argument('--keep-frames', action='store_true',
                        help='Keep PNG frames for inspection (saved in frames/ directory)')
    
    args = parser.parse_args()
    
    process_video(
        input_path=args.input,
        output_path=args.output,
        key_color=tuple(args.key_color),
        transparency=args.transparency,
        tolerance=args.tolerance,
        highlight=args.highlight,
        shadow=args.shadow,
        pedestal=args.pedestal,
        spill_suppression=args.spill_suppression,
        contrast=args.contrast,
        mid_point=args.mid_point,
        choke=args.choke,
        soften=args.soften,
        output_mode=args.output_mode,
        keep_frames=args.keep_frames
    )


if __name__ == '__main__':
    main()
