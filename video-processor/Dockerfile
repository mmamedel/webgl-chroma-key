FROM python:3.11-slim-bookworm

# Install system dependencies for OpenGL, GLFW, OpenCV, and virtual X11
RUN apt-get update && apt-get install -y --no-install-recommends \
    # OpenGL libraries (Mesa for software rendering)
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    # GLFW dependencies
    libglfw3 \
    libglfw3-dev \
    libx11-6 \
    libxcursor1 \
    libxi6 \
    libxrandr2 \
    libxinerama1 \
    # Virtual X server (for headless GLFW)
    xvfb \
    # OpenCV dependencies
    libgomp1 \
    libgfortran5 \
    libopenblas0 \
    # Build tools (for any compiled extensions)
    gcc \
    g++ \
    # Dependencies for building FFmpeg
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install newer FFmpeg from static build (version 7.x for better ProRes support)
RUN wget -q https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz && \
    tar xf ffmpeg-release-amd64-static.tar.xz && \
    cd ffmpeg-*-amd64-static && \
    mv ffmpeg ffprobe /usr/local/bin/ && \
    cd .. && \
    rm -rf ffmpeg-*-amd64-static* && \
    ffmpeg -version

# Set environment variables for OpenGL software rendering
ENV MESA_GL_VERSION_OVERRIDE=3.3
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV GALLIUM_DRIVER=llvmpipe
ENV DISPLAY=:99

# Create app directory
WORKDIR /app

# Copy requirements first for better caching (build context is project root)
COPY video-processor/requirements.txt .

# Install Python dependencies
# Note: opencv-python-headless is used instead of opencv-python for Docker (no GUI)
# Debian has binary wheels so this is MUCH faster than Alpine
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir opencv-python-headless

# Copy shaders
COPY src/lib/shaders /app/src/lib/shaders

# Copy application files
COPY video-processor/process_video.py .
COPY video-processor/test_setup.py .
COPY video-processor/docker-entrypoint.sh /usr/local/bin/

# Make entrypoint executable
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create directories for input/output
RUN mkdir -p /input /output

# Set entrypoint to start Xvfb
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command
CMD ["python", "process_video.py", "--help"]
