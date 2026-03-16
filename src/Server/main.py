import sys
import argparse
import struct
import time
import signal
import math
import os
from unittest.mock import MagicMock

# Mock hardware modules for local testing if they are missing
def mock_hardware():
    modules = [
        'rpi_ws281x', 'smbus', 'spidev', 'fcntl'
    ]
    # Check if we are on a Raspberry Pi (Device Tree Model file exists)
    is_pi = os.path.exists('/sys/firmware/devicetree/base/model')
    # Force mocks ONLY if we are in a container AND NOT on a Pi (e.g. Mac/PC)
    force_mock = os.environ.get('CONTAINER') == 'true' and not is_pi

    for mod in modules:
        try:
            if force_mock and mod != 'fcntl': # Keep fcntl real if possible, it's standard Linux
                raise ImportError("Forcing mock in container")
            __import__(mod)
        except ImportError:
            # print(f"Warning: {mod} not found. Using mock for local testing.")
            sys.modules[mod] = MagicMock()
            if mod == 'smbus':
                sys.modules[mod].SMBus.return_value.read_byte.return_value = 0

    # Guardrail: Configure gpiozero to use MockFactory on non-Pi hardware
    # This prevents BadPinFactory errors on macOS/Windows
    try:
        # Check if we are in a container OR not on a Pi
        if not is_pi:
            import gpiozero
            from gpiozero.pins.mock import MockFactory
            from gpiozero import Device
            Device.pin_factory = MockFactory()
    except (ImportError, Exception):
        pass

mock_hardware()

from server import Server
import threading
import multiprocessing
from message import Message_Parse
from command import Command
from led import Led
from camera import Camera
from car import Car
from buzzer import Buzzer
from Thread import stop_thread
from threading import Thread

class PiCarServer:
    def __init__(self):
        self.tcp_server = Server()
        self.command = Command()
        self.led = Led()
        # Explicitly turn off LEDs on startup to ensure a clean state
        if self.led.is_support_led_function:
            self.led.colorBlink(0)
        self.car = Car()
        self.buzzer = Buzzer()
        self.camera = Camera(stream_size=(400, 300))
        self.queue_cmd = multiprocessing.Queue()
        self.cmd_parse = Message_Parse()
        self.queue_led = multiprocessing.Queue()
        self.led_parse = Message_Parse()

        self.cmd_thread = None
        self.video_thread = None
        self.car_thread = None
        self.led_process = None
        self.action_process = None
        self.cmd_thread_is_running = False
        self.video_thread_is_running = False
        self.car_thread_is_running = False
        self.led_process_is_running = False
        self.action_process_is_running = False
        self.car_mode = 1
        self.rotation_flag = False
        self.send_sonic_data_time = time.time()
        self.send_light_data_time = time.time()
        self.send_line_data_time = time.time()
        self.led_mode = 0

    def stop_car(self):
        self.led.colorBlink(0)
        self.camera.stop_stream()
        self.camera.close()
        self.car.close()

    def start(self):
        self.tcp_server.start_tcp_servers()
        self.set_threading_cmd_receive(True)
        self.set_threading_video_send(True)
        self.set_threading_car_task(True)
        self.set_process_led_running(True)

    def send_sonic_data(self):
        if time.time() - self.send_sonic_data_time > 0.5:
            self.send_sonic_data_time = time.time()
            if self.tcp_server.get_command_server_busy() == False:
                distance = self.car.sonic.get_distance()
                cmd = self.command.CMD_MODE + "#3#{:.2f}".format(distance) + "\n"
                self.tcp_server.send_data_to_command_client(cmd)
                #print(cmd)

    def send_light_data(self):
        if time.time() - self.send_light_data_time > 0.3:
            self.send_light_data_time = time.time()
            if self.tcp_server.get_command_server_busy() == False:
                adc_light_1 = self.car.adc.read_adc(0)
                adc_light_2 = self.car.adc.read_adc(1)
                cmd = self.command.CMD_MODE + "#2#{:.2f}#{:.2f}".format(adc_light_1, adc_light_2) + "\n" 
                self.tcp_server.send_data_to_command_client(cmd)
                #print(cmd)
    def send_line_data(self):
        if time.time() - self.send_line_data_time > 0.3:
            self.send_line_data_time = time.time()
            if self.tcp_server.get_command_server_busy() == False:
                ir_value_1 = self.car.infrared.read_one_infrared(1)
                ir_value_2 = self.car.infrared.read_one_infrared(2)
                ir_value_3 = self.car.infrared.read_one_infrared(3)
                cmd = self.command.CMD_MODE + "#4#{:.2f}#{:.2f}#{:.2f}".format(ir_value_1, ir_value_2, ir_value_3) + "\n"
                self.tcp_server.send_data_to_command_client(cmd)
                #print(cmd)
    def send_power_data(self):
        if self.tcp_server.get_command_server_busy() == False:
            power = self.car.adc.read_adc(2) * (3 if self.car.adc.pcb_version == 1 else 2)
            cmd = self.command.CMD_POWER + "#" + str(power) + "\n"
            self.tcp_server.send_data_to_command_client(cmd)
            #print(cmd)

    def set_threading_cmd_receive(self, state, close_time=0.3):
        if self.cmd_thread is None:
            buf_state = False
        else:
            buf_state = self.cmd_thread.is_alive()
        if state != buf_state:
            if state:
                self.cmd_thread_is_running = True
                self.cmd_thread = threading.Thread(target=self.threading_cmd_receive)
                self.cmd_thread.start()
            else:
                self.cmd_thread_is_running = False
                if self.cmd_thread is not None:
                    self.cmd_thread.join(close_time)
                    self.cmd_thread = None

    def threading_cmd_receive(self):
        while self.cmd_thread_is_running:
            cmd_queue = self.tcp_server.read_data_from_command_server()
            if cmd_queue.qsize() > 0:
                client_address, all_message = cmd_queue.get()
                main_message = all_message.strip()
                if "\n" in main_message:
                    for msg in main_message.split("\n"):
                        self.queue_cmd.put(msg)
                else:
                    self.queue_cmd.put(main_message)
            while not self.queue_cmd.empty():
                msg = self.queue_cmd.get()
                self.cmd_parse.clear_parameters()
                self.cmd_parse.parse(msg)
                print("{}".format(self.cmd_parse.input_string))
                if self.cmd_parse.command_string == self.command.CMD_LED:
                    self.queue_led.put(msg)
                elif self.cmd_parse.command_string == self.command.CMD_LED_MOD:
                    self.queue_led.put(msg)
                else:
                    if self.cmd_parse.command_string == self.command.CMD_SONIC:
                        self.send_sonic_data()
                    elif self.cmd_parse.command_string == self.command.CMD_LIGHT:
                        self.send_light_data()
                    elif self.cmd_parse.command_string == self.command.CMD_LINE:
                        self.send_line_data()
                    elif self.cmd_parse.command_string == self.command.CMD_POWER:
                        self.send_power_data()
                    elif self.cmd_parse.command_string == self.command.CMD_BUZZER:
                        self.buzzer.set_state(self.cmd_parse.int_parameter[0])
                    elif self.cmd_parse.command_string == self.command.CMD_SERVO:
                        try:
                            print(len(self.cmd_parse.int_parameter))
                            data1 = str(self.cmd_parse.int_parameter[0])
                            data2 = int(self.cmd_parse.int_parameter[1])
                            print(data1, data2)
                            if data1 == None or data2 == None:
                                continue
                            self.car.servo.set_servo_pwm(data1, data2)
                        except Exception as e:
                            print(e)
                    elif self.cmd_parse.command_string == self.command.CMD_MOTOR:
                        self.car_mode = 1
                        try:
                            duty = [int(self.cmd_parse.int_parameter[i]) for i in range(4)]
                            if duty[0] == None or duty[1]== None or duty[2] == None or duty[3] == None:
                                continue
                            scale_factor = 0.8
                            scaled_duty = [int(round(d * scale_factor)) for d in duty]
                            self.car.motor.set_motor_model(scaled_duty[0], scaled_duty[1], scaled_duty[2], scaled_duty[3])
                        except:
                            pass
                    elif self.cmd_parse.command_string == self.command.CMD_M_MOTOR:
                        self.car_mode = 1
                        duty = [int(self.cmd_parse.int_parameter[i]) for i in range(4)]
                        LX = -int((duty[1] * math.sin(math.radians(duty[0]))))
                        LY = int(duty[1] * math.cos(math.radians(duty[0])))
                        RX = int(duty[3] * math.sin(math.radians(duty[2])))
                        RY = int(duty[3] * math.cos(math.radians(duty[2])))
                        FR = LY - LX + RX
                        FL = LY + LX - RX
                        BL = LY - LX - RX
                        BR = LY + LX + RX
                        if duty[0] == None or duty[1]== None or duty[2] == None or duty[3] == None:
                            continue
                        self.car.motor.set_motor_model(FL, BL, FR, BR)
                    elif self.cmd_parse.command_string == self.command.CMD_CAR_ROTATE:
                        try:
                            self.car_mode = 1
                            duty = [int(self.cmd_parse.int_parameter[i]) for i in range(4)]
                            if duty[3] == 0:
                                try:
                                    stop_thread(Rotate_Mode)
                                    self.rotation_flag = False
                                except:
                                    pass
                                LX = -int((duty[1] * math.sin(math.radians(duty[0]))))
                                LY = int(duty[1] * math.cos(math.radians(duty[0])))
                                RX = int(duty[3] * math.sin(math.radians(duty[2])))
                                RY = int(duty[3] * math.cos(math.radians(duty[2])))
                                FR = LY - LX + RX
                                FL = LY + LX - RX
                                BL = LY - LX - RX
                                BR = LY + LX + RX
                                if duty[0] == None or duty[1]== None or duty[2] == None:
                                    continue
                                self.car.motor.set_motor_model(FL, BL, FR, BR)
                            elif self.rotation_flag == False:
                                try:
                                    stop_thread(self.Rotate_Mode)
                                except:
                                    pass
                                self.rotation_flag = True
                                Rotate_Mode = Thread(target=self.car.mode_rotate, args=(duty[2],))
                                Rotate_Mode.start()
                        except Exception as e:
                            print(e)
                    elif self.cmd_parse.command_string == self.command.CMD_MODE:
                        if self.cmd_parse.int_parameter[0] == 0:
                            self.car_mode = 1
                            self.car.motor.set_motor_model(0, 0, 0, 0)
                            print("Car Mode: Manual Car")
                        elif self.cmd_parse.int_parameter[0] == 1:
                            self.car_mode = 2
                            print("Car Mode: Light Car")
                        elif self.cmd_parse.int_parameter[0] == 2:
                            self.car_mode = 3
                            print("Car Mode: Infrared Car")
                        elif self.cmd_parse.int_parameter[0] == 3:
                            self.car_mode = 4
                            print("Car Mode: Ultrasonic Car")
                    
            if self.queue_cmd.empty():
                time.sleep(0.001)

    def set_threading_car_task(self, state, close_time=0.3):
        if self.car_thread is None:
            buf_state = False
        else:
            buf_state = self.car_thread.is_alive()
        if state != buf_state:
            if state:
                self.car_thread_is_running = True
                self.car_thread = threading.Thread(target=self.threading_car_task)
                self.car_thread.start()
            else:
                self.car_thread_is_running = False
                if self.car_thread is not None:
                    self.car_thread.join(close_time)
                    self.car_thread = None

    def threading_car_task(self):
        while self.car_thread_is_running:
            if self.car_mode == 1:
                pass
            elif self.car_mode == 2:
                self.car.mode_light()
                self.send_light_data()
            elif self.car_mode == 3:
                self.car.mode_infrared()
            elif self.car_mode == 4:
                self.car.mode_ultrasonic()
                self.send_sonic_data()
            time.sleep(0.01)


    def set_threading_video_send(self, state, close_time=0.3):
        if self.video_thread is None:
            buf_state = False
        else:
            buf_state = self.video_thread.is_alive()
        if state != buf_state:
            if state:
                self.video_thread_is_running = True
                self.video_thread = threading.Thread(target=self.threading_video_send)
                self.video_thread.start()
            else:
                self.video_thread_is_running = False
                if self.video_thread is not None:
                    self.video_thread.join(close_time)
                    self.video_thread = None

    def threading_video_send(self):
        while self.video_thread_is_running:
            if self.tcp_server.is_video_server_connected():
                self.camera.start_stream()
                while self.tcp_server.is_video_server_connected():
                    frame = self.camera.get_frame()
                    lenFrame = len(frame)
                    lengthBin = struct.pack('<I', lenFrame)
                    try:
                        self.tcp_server.send_data_to_video_client(lengthBin)
                        self.tcp_server.send_data_to_video_client(frame)
                    except:
                        break
                self.camera.stop_stream()
            else:
                time.sleep(0.1)

    def set_process_led_running(self, state, close_time=0.3):
        if self.led_process is None:
            buf_state = False
        else:
            buf_state = self.led_process.is_alive()
        if state != buf_state:
            if state:
                self.led_process_is_running = True
                self.led_process = threading.Thread(target=self.process_led_running, args=(self.queue_led,))
                self.led_process.start()
            else:
                self.led_process_is_running = False
                if self.led_process is not None:
                    self.led_process.join(close_time)
                    self.led_process = None

    def process_led_running(self, queue_led):
        try:
            while self.led_process_is_running:
                if not queue_led.empty():
                    queue_buf_cmd = queue_led.get()
                    self.led_parse.clear_parameters()
                    self.led_parse.parse(queue_buf_cmd)
                    print("LED: {}".format(queue_buf_cmd))

                    if self.led_parse.command_string == "CMD_LED" and self.led_mode == 1:
                        try:
                            data1 = int(self.led_parse.int_parameter[0])
                            data2 = int(self.led_parse.int_parameter[1])
                            data3 = int(self.led_parse.int_parameter[2])
                            data4 = int(self.led_parse.int_parameter[3])
                            if data1==None or data2==None or data3==None or data4==None:
                                continue
                            self.led.ledIndex(data1,data2,data3,data4)
                        except:
                            pass
                    if self.led_parse.command_string == "CMD_LED_MOD":
                        if self.led_parse.int_parameter[0] == 1:
                            self.led_mode = 1
                        elif self.led_parse.int_parameter[0] == 2:
                            self.led_mode = 2
                        elif self.led_parse.int_parameter[0] == 3:
                            self.led_mode = 3
                        elif self.led_parse.int_parameter[0] == 4:
                            self.led_mode = 4
                        elif self.led_parse.int_parameter[0] == 5:
                            self.led_mode = 5
                        else:
                            self.led_mode = 0
                if self.led_mode == 1:
                    pass
                elif self.led_mode == 2:
                    self.led.following()
                elif self.led_mode == 3:
                    self.led.colorBlink(1)
                elif self.led_mode == 4:
                    self.led.rainbowbreathing()
                elif self.led_mode == 5:
                    self.led.rainbowCycle()
                elif self.led_mode == 0:
                    self.led.colorBlink(0)
                        
                time.sleep(0.01)

        except KeyboardInterrupt:
            print("LED process interrupted, cleaning up...")
            self.led.colorBlink(0)

    def stop(self):
        self.set_threading_cmd_receive(False)
        self.set_threading_video_send(False)
        self.set_threading_car_task(False)
        self.set_process_led_running(False)
        if self.tcp_server:
            self.tcp_server.stop_tcp_servers()
            self.tcp_server = None
        self.stop_car()
        if self.cmd_thread and self.cmd_thread.is_alive():
            self.cmd_thread.join(0.1)
        if self.video_thread and self.video_thread.is_alive():
            self.video_thread.join(0.1)
        if self.car_thread and self.car_thread.is_alive():
            self.car_thread.join(0.1)
        if self.led_process and self.led_process.is_alive():
            self.led_process.join(0.1)
        sys.exit(1)

if __name__ == '__main__':
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Freenove 4WD Smart Car Server')
    parser.add_argument('-t', '--terminal', action='store_true', help='Run in terminal mode (no GUI)')
    parser.add_argument('-n', '--no-gui', action='store_true', help='Run in terminal mode (no GUI)')
    
    args = parser.parse_args()
    
    server = PiCarServer()
    server.start()

    def signal_handler(sig, frame):
        print("Caught Ctrl+C, stopping application...")
        server.stop()
        
    # Handle Ctrl+C gracefully
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        signal_handler(None, None)
        
