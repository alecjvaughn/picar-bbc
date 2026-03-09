def test_Led():
    import time
    from led import Led
    led=Led()
    try:
        led.ledIndex(0x01, 255,   0,   0)      #Red
        led.ledIndex(0x02, 255, 125,   0)      #orange
        led.ledIndex(0x04, 255, 255,   0)      #yellow
        led.ledIndex(0x08,   0, 255,   0)      #green
        led.ledIndex(0x10,   0, 255, 255)      #cyan-blue
        led.ledIndex(0x20,   0,   0, 255)      #blue
        led.ledIndex(0x40, 128,   0, 128)      #purple
        led.ledIndex(0x80, 255, 255, 255)      #white
        print ("The LED has been lit, the color is red orange yellow green cyan-blue blue white")
        time.sleep(3)               #wait 3s
        led.colorBlink(0)  #turn off the light
        print ("\nEnd of program")
    except KeyboardInterrupt:
        led.colorBlink(0)  #turn off the light
        print ("\nEnd of program") 
        
def test_Motor(): 
    import time
    from motor import Ordinary_Car  
    PWM = Ordinary_Car()    
    try:
        PWM.set_motor_model(1000,1000,1000,1000)         #Forward
        print ("The car is moving forward")
        time.sleep(1)
        PWM.set_motor_model(-1000,-1000,-1000,-1000)     #Back
        print ("The car is going backwards")
        time.sleep(1)
        PWM.set_motor_model(-1500,-1500,2000,2000)       #Turn left
        print ("The car is turning left")
        time.sleep(1)
        PWM.set_motor_model(2000,2000,-1500,-1500)       #Turn right 
        print ("The car is turning right")  
        time.sleep(1)
        PWM.set_motor_model(0,0,0,0)                     #Stop
        print ("\nEnd of program")
    except KeyboardInterrupt:
        print ("\nEnd of program")
    finally:
        PWM.close() # Close the PWM instance

def test_Ultrasonic(duration=None):
    import time
    from ultrasonic import Ultrasonic
    # Initialize the Ultrasonic instance with default pin numbers and max distance
    ultrasonic = Ultrasonic()
    start_time = time.time()
    try:
        print("Program is starting ...")
        while True:
            if duration and (time.time() - start_time > duration):
                break
            distance = ultrasonic.get_distance()  # Get the distance measurement in centimeters
            if distance is not None:
                print(f"Ultrasonic distance: {distance}cm")  # Print the distance measurement
            time.sleep(0.5)  # Wait for 0.5 seconds
    except KeyboardInterrupt:  # Handle keyboard interrupt (Ctrl+C)
        ultrasonic.close()
    finally:
        print("\nEnd of program")  # Print an end message

def test_Infrared(duration=None):
    import time
    from infrared import Infrared
    # Create an Infrared object
    infrared = Infrared()
    start_time = time.time()
    try:
        print("Program is starting ...")
        # Continuously read and print the combined value of all infrared sensors
        while True:
            if duration and (time.time() - start_time > duration):
                break
            ir1_value = infrared.read_one_infrared(1)
            ir2_value = infrared.read_one_infrared(2)
            ir3_value = infrared.read_one_infrared(3)
            if ir1_value != 1 and ir2_value == 1 and ir3_value != 1:
                print ('Middle')
            elif ir1_value != 1 and ir2_value != 1 and ir3_value == 1:
                print ('Right')
            elif ir1_value == 1 and ir2_value != 1 and ir3_value != 1:
                print ('Left')
    except KeyboardInterrupt:
        # Close the Infrared object and print a message when interrupted
        infrared.close()
        print("\nEnd of program")

def test_Servo(duration=None):
    import time
    from servo import Servo
    servo = Servo()
    start_time = time.time()
    try:
        print ("Program is starting ...")
        while True:
            if duration and (time.time() - start_time > duration):
                break
            for i in range(50,110,1):
                servo.set_servo_pwm('0',i)
                time.sleep(0.01)
            for i in range(110,50,-1):
                servo.set_servo_pwm('0',i)
                time.sleep(0.01)
            for i in range(80,150,1):
                servo.set_servo_pwm('1',i)
                time.sleep(0.01)
            for i in range(150,80,-1):
                servo.set_servo_pwm('1',i)
                time.sleep(0.01)   
    except KeyboardInterrupt:
        servo.set_servo_pwm('0',90)
        servo.set_servo_pwm('1',90)
    finally:
        print ("\nEnd of program")
        
def test_Adc(duration=None):
    import time
    from adc import ADC
    adc = ADC()
    start_time = time.time()
    try:
        print ("Program is starting ...")
        while True:
            if duration and (time.time() - start_time > duration):
                break
            Left_IDR = adc.read_adc(0)
            print ("The photoresistor voltage on the left is "+str(Left_IDR)+"V")
            Right_IDR = adc.read_adc(1)
            print ("The photoresistor voltage on the right is "+str(Right_IDR)+"V")
            Power = adc.read_adc(2) * (3 if adc.pcb_version == 1 else 2)
            print ("The battery voltage is "+str(Power)+"V")
            time.sleep(1)
            print ('\n')
    except KeyboardInterrupt:
        print ("\nEnd of program")

def test_Buzzer():
    import time
    from buzzer import Buzzer
    buzzer = Buzzer()
    try:
        print ("Program is starting ...")
        buzzer.set_state(True)
        time.sleep(1)
        print ("1S")
        time.sleep(1)
        print ("2S")
        time.sleep(1)
        print ("3S")
        buzzer.set_state(False)
    except KeyboardInterrupt:
        buzzer.set_state(False)
    finally:
        print ("\nEnd of program")
           
def test_Camera():
    import time
    from camera import Camera
    try:
        print ("Program is starting ...")
        camera = Camera()
        print ("Camera initialized. Starting preview for 5 seconds...")
        camera.start_image(show_preview=False)
        time.sleep(5)
        filename = "/tmp/test_camera.jpg"
        print (f"Capturing test image to '{filename}'...")
        camera.save_image(filename)
        camera.close()
        print ("\nEnd of program")
    except Exception as e:
        print (f"Camera Error: {e}")
        print ("\nEnd of program")

def test_Motor_All():
    print("\n=== Testing All Motor Components ===")
    print(">> Testing DC Motors...")
    test_Motor()
    print(">> Testing Servos (5s)...")
    test_Servo(duration=5)

def test_Non_Motor_All():
    print("\n=== Testing All Non-Motor Components ===")
    test_Led()
    test_Buzzer()
    test_Camera()
    print(">> Testing Ultrasonic (5s)...")
    test_Ultrasonic(duration=5)
    print(">> Testing Infrared (5s)...")
    test_Infrared(duration=5)
    print(">> Testing ADC (5s)...")
    test_Adc(duration=5)

# Main program logic follows:
if __name__ == '__main__':
    print ('Program is starting ... ')
    import sys
    if len(sys.argv)<2:
        print ("Parameter error: Please assign the device")
        exit() 
    if sys.argv[1] == 'Led':
        test_Led()
    elif sys.argv[1] == 'Motor':
        test_Motor()
    elif sys.argv[1] == 'Ultrasonic':
        test_Ultrasonic()
    elif sys.argv[1] == 'Infrared':
        test_Infrared()        
    elif sys.argv[1] == 'Servo': 
        test_Servo()               
    elif sys.argv[1] == 'ADC':   
        test_Adc()  
    elif sys.argv[1] == 'Buzzer':   
        test_Buzzer()  
    elif sys.argv[1] == 'Camera':
        test_Camera()
    elif sys.argv[1] == 'Motor-All':
        test_Motor_All()
    elif sys.argv[1] == 'Non-Motor-All':
        test_Non_Motor_All()
