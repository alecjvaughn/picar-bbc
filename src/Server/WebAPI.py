from flask import Flask, jsonify, request
from flasgger import Swagger
import socket
import sys
import os

# Ensure we can import from sibling directories to get Command definitions
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

try:
    from Client.Command import COMMAND as cmd
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

app = Flask(__name__)
swagger = Swagger(app)

# Configuration to match the existing TCP Server
TCP_IP = '127.0.0.1'
TCP_PORT = 5000
INTERVAL_CHAR = '#'
END_CHAR = '\n'

def send_command(command_str):
    """Sends a raw command string to the local TCP server."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect((TCP_IP, TCP_PORT))
            s.sendall(command_str.encode('utf-8'))
        return True
    except Exception as e:
        print(f"Connection Error: {e}")
        return False

@app.route('/api/status', methods=['GET'])
def status():
    """
    Get API Status
    ---
    tags:
      - System
    responses:
      200:
        description: API status
    """
    return jsonify({"status": "online", "backend": f"{TCP_IP}:{TCP_PORT}"})

@app.route('/api/move', methods=['POST'])
def move_control():
    """
    Control motors.
    ---
    tags:
      - Movement
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - action
          properties:
            action:
              type: string
              enum: [forward, backward, left, right, stop]
    responses:
      200:
        description: Success
    """
    data = request.json
    action = data.get('action')
    
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
        return jsonify({"error": "Invalid action"}), 400

    # Construct: CMD_MOTOR#1500#1500#1500#1500\n
    full_cmd = f"{cmd.CMD_MOTOR}{INTERVAL_CHAR}{payload}{END_CHAR}"

    if send_command(full_cmd):
        return jsonify({"status": "success", "action": action})
    else:
        return jsonify({"error": "Failed to communicate with robot server"}), 500

@app.route('/api/servo', methods=['POST'])
def servo_control():
    """
    Control servos (Camera movement).
    ---
    tags:
      - Servos
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - id
            - angle
          properties:
            id:
              type: integer
              description: 0 for horizontal, 1 for vertical
            angle:
              type: integer
              description: 0-180 degrees
    responses:
      200:
        description: Success
    """
    data = request.json
    servo_id = data.get('id')
    angle = data.get('angle')
    
    if servo_id is None or angle is None:
        return jsonify({"error": "Missing id or angle"}), 400
        
    # Construct: CMD_SERVO#0#90\n
    full_cmd = f"{cmd.CMD_SERVO}{INTERVAL_CHAR}{servo_id}{INTERVAL_CHAR}{angle}{END_CHAR}"
    
    if send_command(full_cmd):
        return jsonify({"status": "success", "servo": servo_id, "angle": angle})
    else:
        return jsonify({"error": "Failed to communicate with robot server"}), 500

@app.route('/api/buzzer', methods=['POST'])
def buzzer_control():
    """
    Control Buzzer.
    ---
    tags:
      - Peripherals
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          properties:
            state:
              type: integer
              description: 1 for on, 0 for off
    responses:
      200:
        description: Success
    """
    data = request.json
    state = data.get('state', 0) # 1 for on, 0 for off
    full_cmd = f"{cmd.CMD_BUZZER}{INTERVAL_CHAR}{state}{END_CHAR}"
    if send_command(full_cmd):
        return jsonify({"status": "success", "state": state})
    return jsonify({"error": "Failed"}), 500

@app.route('/api/led', methods=['POST'])
def led_control():
    """
    Control LED.
    ---
    tags:
      - Peripherals
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          properties:
            mode:
              type: integer
              description: 0=Off, 1=Manual, 2=Following, 3=Blink, 4=RainbowBreathing, 5=RainbowCycle
            index:
              type: integer
              description: bitmask for manual mode (requires mode 1)
            r:
              type: integer
            g:
              type: integer
            b:
              type: integer
    responses:
      200:
        description: Success
    """
    data = request.json
    
    if 'mode' in data:
        mode = data['mode']
        full_cmd = f"{cmd.CMD_LED_MOD}{INTERVAL_CHAR}{mode}{END_CHAR}"
        if send_command(full_cmd):
             return jsonify({"status": "success", "led_mode": mode})
    
    elif 'index' in data and 'r' in data and 'g' in data and 'b' in data:
        index = data['index']
        r = data['r']
        g = data['g']
        b = data['b']
        full_cmd = f"{cmd.CMD_LED}{INTERVAL_CHAR}{index}{INTERVAL_CHAR}{r}{INTERVAL_CHAR}{g}{INTERVAL_CHAR}{b}{END_CHAR}"
        if send_command(full_cmd):
            return jsonify({"status": "success", "led_color": {"index": index, "r": r, "g": g, "b": b}})
            
    return jsonify({"error": "Invalid parameters"}), 400

@app.route('/api/car_mode', methods=['POST'])
def car_mode_control():
    """
    Control Car Mode.
    ---
    tags:
      - System
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          properties:
            mode:
              type: string
              enum: [manual, light, infrared, ultrasonic]
    responses:
      200:
        description: Success
    """
    data = request.json
    mode_str = data.get('mode')
    
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
            return jsonify({"status": "success", "car_mode": mode_str})
            
    return jsonify({"error": "Invalid mode. Available: manual, light, infrared, ultrasonic"}), 400

@app.route('/api/mecanum', methods=['POST'])
def mecanum_control():
    """
    Control Mecanum wheels.
    ---
    tags:
      - Movement
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          properties:
            move_angle:
              type: integer
            move_speed:
              type: integer
            rotate_angle:
              type: integer
            rotate_speed:
              type: integer
    responses:
      200:
        description: Success
    """
    data = request.json
    move_angle = data.get('move_angle', 0)
    move_speed = data.get('move_speed', 0)
    rotate_angle = data.get('rotate_angle', 0)
    rotate_speed = data.get('rotate_speed', 0)
    
    full_cmd = f"{cmd.CMD_M_MOTOR}{INTERVAL_CHAR}{move_angle}{INTERVAL_CHAR}{move_speed}{INTERVAL_CHAR}{rotate_angle}{INTERVAL_CHAR}{rotate_speed}{END_CHAR}"
    
    if send_command(full_cmd):
        return jsonify({"status": "success", "mecanum": data})
    return jsonify({"error": "Failed"}), 500

if __name__ == '__main__':
    # Run on port 5001 to avoid conflict with the TCP server on 5000
    app.run(host='0.0.0.0', port=5001)