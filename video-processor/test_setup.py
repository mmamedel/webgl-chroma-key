#!/usr/bin/env python3
"""
Quick test to verify PyOpenGL setup
"""

try:
    import cv2
    print("✅ OpenCV installed")
except ImportError:
    print("❌ OpenCV not installed: pip install opencv-python")

try:
    from OpenGL.GL import *
    print("✅ PyOpenGL installed")
except ImportError:
    print("❌ PyOpenGL not installed: pip install PyOpenGL PyOpenGL-accelerate")

try:
    import glfw
    if glfw.init():
        print("✅ GLFW initialized")
        glfw.terminate()
    else:
        print("⚠️  GLFW installed but failed to initialize")
except ImportError:
    print("❌ GLFW not installed: pip install glfw")

try:
    import numpy as np
    print("✅ NumPy installed")
except ImportError:
    print("❌ NumPy not installed: pip install numpy")

from pathlib import Path
project_root = Path(__file__).parent.parent
shader_dir = project_root / 'src' / 'lib' / 'shaders'

if (shader_dir / 'basic.vert').exists():
    print("✅ Vertex shader found")
else:
    print("❌ Vertex shader not found at", shader_dir / 'basic.vert')

if (shader_dir / 'phase1.frag').exists():
    print("✅ Fragment shader found")
else:
    print("❌ Fragment shader not found at", shader_dir / 'phase1.frag')

video_path = project_root / 'static' / 'green-screen-sample.webm'
if video_path.exists():
    print(f"✅ Test video found")
else:
    print(f"❌ Test video not found at {video_path}")

bg_path = project_root / 'static' / 'bg.jpg'
if bg_path.exists():
    print(f"✅ Background image found")
else:
    print(f"❌ Background image not found at {bg_path}")

print("\n" + "="*50)
print("Setup verification complete!")
print("If all checks passed, run:")
print("  python process_video.py -i ../static/green-screen-sample.webm -o ../output.mp4 -b ../static/bg.jpg")
