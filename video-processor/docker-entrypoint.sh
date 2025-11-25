#!/bin/bash
set -e

# Start Xvfb (virtual X server) in the background
Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!

# Wait a moment for Xvfb to start
sleep 1

# Execute the main command
exec "$@"
