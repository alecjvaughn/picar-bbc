#!/bin/bash
set -e

# Start the main hardware control process in the background
python3 /app/Server/main.py --no-gui &

# Start the Web API in the foreground.
# Using 'exec' ensures that it becomes the main process (PID 1),
# allowing it to receive signals like 'docker stop' correctly.
exec python3 /app/Server/WebAPI.py