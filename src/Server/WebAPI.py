from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional
import socket
import sys
import os
import uvicorn
import struct
import asyncio
from datetime import datetime

# Ensure we can import from sibling directories to get Command definitions
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

try:
    from Client.Qt.Command import COMMAND as cmd
except ImportError:
    # Fallback if import fails
    class cmd:
        CMD_MOTOR = "CMD_MOTOR"
        CMD_SERVO = "CMD_SERVO"
        CMD_BUZZER = "CMD_BUZZER"
        CMD_LED = "CMD_LED"
        CMD_LED_MOD = "CMD_LED_MOD"
        CMD_MODE = "CMD_MODE"
        CMD_M_MOTOR = "CMD_M_MOTOR"

app = FastAPI(title="PiCar Web API", description="API to control the PiCar")

# Allow React frontend to communicate with this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace "*" with your React app's IP/Port
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration to match the existing TCP Server
TCP_IP = '127.0.0.1'
TCP_PORT = 5050
VIDEO_PORT = 8080
INTERVAL_CHAR = '#'
END_CHAR = '\n'

log_buffer = []
log_counter = 0

def app_log(msg: str):
    """Add a message to the internal log buffer."""
    global log_counter
    timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    log_entry = {"id": log_counter, "msg": f"[{timestamp}] {msg}"}
    log_counter += 1
    print(log_entry["msg"])
    log_buffer.append(log_entry)
    if len(log_buffer) > 100:
        log_buffer.pop(0)

def send_command(command_str: str) -> bool:
    """Sends a raw command string to the local TCP server."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect((TCP_IP, TCP_PORT))
            s.sendall(command_str.encode('utf-8'))
        app_log(f"SENT: {command_str.strip()}")
        return True
    except Exception as e:
        app_log(f"ERROR: Failed to send '{command_str.strip()}' - {e}")
        return False

# --- Pydantic Models for Request Validation ---

class MoveRequest(BaseModel):
    action: str

class ServoRequest(BaseModel):
    id: int
    angle: int

class BuzzerRequest(BaseModel):
    state: int = 0

class LedRequest(BaseModel):
    mode: Optional[int] = None
    index: Optional[int] = None
    r: Optional[int] = None
    g: Optional[int] = None
    b: Optional[int] = None

class CarModeRequest(BaseModel):
    mode: str

class MecanumRequest(BaseModel):
    move_angle: int = 0
    move_speed: int = 0
    rotate_angle: int = 0
    rotate_speed: int = 0

# --- API Routes ---

@app.get('/api/logs_stream', tags=["System"])
async def logs_stream():
    """Streams internal API logs using Server-Sent Events (SSE)."""
    async def event_generator():
        last_id = -1
        # Send current history first so UI populates immediately
        if log_buffer:
            for entry in log_buffer:
                yield f"data: {entry['msg']}\n\n"
                last_id = entry['id']
        while True:
            for entry in log_buffer:
                if entry['id'] > last_id:
                    yield f"data: {entry['msg']}\n\n"
                    last_id = entry['id']
            await asyncio.sleep(0.5)
    return StreamingResponse(event_generator(), media_type="text/event-stream")

def recvall(sock, count):
    """Helper function to reliably receive exactly `count` bytes from a socket."""
    buf = b''
    while count:
        newbuf = sock.recv(count)
        if not newbuf: return None
        buf += newbuf
        count -= len(newbuf)
    return buf

def video_stream_generator():
    """Connects to the local raw TCP video server and yields MJPEG HTTP frames."""
    client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        client_socket.connect((TCP_IP, VIDEO_PORT))
        while True:
            # Read the 4-byte length header
            length_bytes = recvall(client_socket, 4)
            if not length_bytes:
                break
            
            # Unpack the length and read the exact number of JPEG bytes
            length = struct.unpack('<I', length_bytes)[0]
            frame = recvall(client_socket, length)
            if not frame:
                break
                
            # Yield the frame in the standard MJPEG multipart format
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
    except Exception as e:
        print(f"Video Stream Error: {e}")
    finally:
        client_socket.close()

@app.get('/api/status', tags=["System"])
def status():
    """Get API Status and verify hardware backend connection"""
    hardware_online = False
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect((TCP_IP, TCP_PORT))
            hardware_online = True
    except Exception:
        pass

    return {"api": "online", "backend": f"{TCP_IP}:{TCP_PORT}", "hardware": "online" if hardware_online else "offline"}

@app.post('/api/move', tags=["Movement"])
def move_control(req: MoveRequest):
    """Control motors. Available actions: forward, backward, left, right, stop"""
    action = req.action
    
    # Standard 4WD Motor PWM values (1500 is roughly mid-speed/forward depending on calibration)
    if action == 'forward':
        payload = f"1500{INTERVAL_CHAR}1500{INTERVAL_CHAR}1500{INTERVAL_CHAR}1500"
    elif action == 'backward':
        payload = f"-1500{INTERVAL_CHAR}-1500{INTERVAL_CHAR}-1500{INTERVAL_CHAR}-1500"
    elif action == 'left':
        payload = f"-1500{INTERVAL_CHAR}-1500{INTERVAL_CHAR}1500{INTERVAL_CHAR}1500"
    elif action == 'right':
        payload = f"1500{INTERVAL_CHAR}1500{INTERVAL_CHAR}-1500{INTERVAL_CHAR}-1500"
    elif action == 'stop':
        payload = f"0{INTERVAL_CHAR}0{INTERVAL_CHAR}0{INTERVAL_CHAR}0"
    else:
        raise HTTPException(status_code=400, detail="Invalid action")

    # Construct: CMD_MOTOR#1500#1500#1500#1500\n
    full_cmd = f"{cmd.CMD_MOTOR}{INTERVAL_CHAR}{payload}{END_CHAR}"

    if send_command(full_cmd):
        return {"status": "success", "action": action}
    else:
        raise HTTPException(status_code=500, detail="Failed to communicate with robot server")

@app.get('/api/video_feed', tags=["Video"])
def video_feed():
    """Streams the camera feed as MJPEG."""
    return StreamingResponse(video_stream_generator(), media_type="multipart/x-mixed-replace; boundary=frame")

@app.post('/api/servo', tags=["Servos"])
def servo_control(req: ServoRequest):
    """Control servos (Camera movement). id: 0 for horizontal, 1 for vertical. angle: 0-180."""
        
    # Construct: CMD_SERVO#0#90\n
    full_cmd = f"{cmd.CMD_SERVO}{INTERVAL_CHAR}{req.id}{INTERVAL_CHAR}{req.angle}{END_CHAR}"
    
    if send_command(full_cmd):
        return {"status": "success", "servo": req.id, "angle": req.angle}
    else:
        raise HTTPException(status_code=500, detail="Failed to communicate with robot server")

@app.post('/api/buzzer', tags=["Peripherals"])
def buzzer_control(req: BuzzerRequest):
    """Control Buzzer. state: 1 for on, 0 for off."""
    full_cmd = f"{cmd.CMD_BUZZER}{INTERVAL_CHAR}{req.state}{END_CHAR}"
    if send_command(full_cmd):
        return {"status": "success", "state": req.state}
    raise HTTPException(status_code=500, detail="Failed")

@app.post('/api/led', tags=["Peripherals"])
def led_control(req: LedRequest):
    """Control LED. mode: 0=Off, 1=Manual, 2=Following, 3=Blink, 4=RainbowBreathing, 5=RainbowCycle"""
    if req.mode is not None:
        full_cmd = f"{cmd.CMD_LED_MOD}{INTERVAL_CHAR}{req.mode}{END_CHAR}"
        if send_command(full_cmd):
             return {"status": "success", "led_mode": req.mode}
    
    elif req.index is not None and req.r is not None and req.g is not None and req.b is not None:
        full_cmd = f"{cmd.CMD_LED}{INTERVAL_CHAR}{req.index}{INTERVAL_CHAR}{req.r}{INTERVAL_CHAR}{req.g}{INTERVAL_CHAR}{req.b}{END_CHAR}"
        if send_command(full_cmd):
            return {"status": "success", "led_color": {"index": req.index, "r": req.r, "g": req.g, "b": req.b}}
            
    raise HTTPException(status_code=400, detail="Invalid parameters")

@app.post('/api/car_mode', tags=["System"])
def car_mode_control(req: CarModeRequest):
    """Control Car Mode. mode: manual, light, infrared, ultrasonic."""
    mode_str = req.mode
    
    mode_map = {
        "manual": "one",
        "light": "two",
        "infrared": "four",
        "ultrasonic": "three"
    }
    
    if mode_str in mode_map:
        val = mode_map[mode_str]
        full_cmd = f"{cmd.CMD_MODE}{INTERVAL_CHAR}{val}{END_CHAR}"
        if send_command(full_cmd):
            return {"status": "success", "car_mode": mode_str}
            
    raise HTTPException(status_code=400, detail="Invalid mode. Available: manual, light, infrared, ultrasonic")

@app.post('/api/mecanum', tags=["Movement"])
def mecanum_control(req: MecanumRequest):
    """Control Mecanum wheels."""
    full_cmd = f"{cmd.CMD_M_MOTOR}{INTERVAL_CHAR}{req.move_angle}{INTERVAL_CHAR}{req.move_speed}{INTERVAL_CHAR}{req.rotate_angle}{INTERVAL_CHAR}{req.rotate_speed}{END_CHAR}"
    
    if send_command(full_cmd):
        return {"status": "success", "mecanum": req.dict()}
    raise HTTPException(status_code=500, detail="Failed")

if __name__ == '__main__':
    # Run on port 5001 to avoid conflict with the TCP server on 5000
    uvicorn.run(app, host='0.0.0.0', port=5001)