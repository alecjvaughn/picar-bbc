import os
os.environ["OPENCV_VIDEOIO_DEBUG"] = "1"
os.environ["OPENCV_LOG_LEVEL"] = "DEBUG"
import cv2
import time
import numpy as np

class Camera:
    def __init__(self, preview_size: tuple = (640, 480), hflip: bool = False, vflip: bool = False, stream_size: tuple = (400, 300)):
        """Initialize the Camera class."""
        self.cap = None
        self.picam2 = None
        self.is_rpi_camera = False
        self.preview_size = preview_size
        self.stream_size = stream_size
        self.hflip = hflip
        self.vflip = vflip
        self.streaming = False
        self.recording = False
        self.video_writer = None

    def _open_camera(self, size: tuple):
        """Internal method to open the camera with a specific resolution."""
        if self.picam2 is not None or (self.cap is not None and self.cap.isOpened()):
            return
        
        # Detect if we are on the physical Raspberry Pi hardware
        is_rpi = False
        try:
            with open('/sys/firmware/devicetree/base/model', 'r') as f:
                if 'Raspberry Pi' in f.read():
                    is_rpi = True
        except FileNotFoundError:
            pass

        if is_rpi:
            try:
                from picamera2 import Picamera2
                self.picam2 = Picamera2()
                # Create a video configuration with the requested size
                config = self.picam2.create_video_configuration(main={"size": size, "format": "RGB888"})
                self.picam2.configure(config)
                self.picam2.start()
                self.is_rpi_camera = True
                print("✅ Picamera2 initialized successfully.")
            except Exception as e:
                print(f"Error initializing Picamera2: {e}")
                self.is_rpi_camera = False
        else:
            # Local mock: Use the computer's built-in webcam
            self.cap = cv2.VideoCapture(0)
            self.is_rpi_camera = False

        if not self.is_rpi_camera and (not self.cap or not self.cap.isOpened()):
            print("Error: Could not open local video device.")
            return

    def start_image(self, show_preview: bool = False) -> None:
        """Start the camera."""
        self._open_camera(self.preview_size)

    def save_image(self, filename: str) -> dict:
        """Capture and save an image to the specified file."""
        if not self.is_rpi_camera and (self.cap is None or not self.cap.isOpened()):
            self._open_camera(self.preview_size)
        elif self.is_rpi_camera and self.picam2 is None:
            self._open_camera(self.preview_size)
            
        ret = False
        frame = None
        
        if self.is_rpi_camera:
            try:
                # Picamera2 automatically handles auto-exposure warmup
                frame = self.picam2.capture_array()
                frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR) # Convert RGB to BGR for OpenCV
                ret = True
            except Exception as e:
                print(f"Picamera2 capture error: {e}")
        else:
            time.sleep(2.0)
            for _ in range(15):
                self.cap.read()
            ret, frame = self.cap.read()

        if ret and frame is not None:
            if self.hflip:
                frame = cv2.flip(frame, 1)
            if self.vflip:
                frame = cv2.flip(frame, 0)
            cv2.imwrite(filename, frame)
            return {"filename": filename}
        else:
            print("Error: Could not read frame.")
            return None

    def start_stream(self, filename: str = None) -> None:
        """Start the video stream or recording."""
        if self.is_rpi_camera and self.picam2 is not None:
            self.picam2.stop()
            config = self.picam2.create_video_configuration(main={"size": self.stream_size, "format": "RGB888"})
            self.picam2.configure(config)
            self.picam2.start()
        elif self.cap is not None and self.cap.isOpened():
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.stream_size[0])
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.stream_size[1])
        else:
            self._open_camera(self.stream_size)

        self.streaming = True
        
        if filename:
            self.recording = True
            # Define the codec and create VideoWriter object
            fourcc = cv2.VideoWriter_fourcc(*'mp4v') 
            w = self.stream_size[0]
            h = self.stream_size[1]
            self.video_writer = cv2.VideoWriter(filename, fourcc, 20.0, (w, h))

    def stop_stream(self) -> None:
        """Stop the video stream or recording."""
        self.streaming = False
        self.recording = False
        if self.video_writer:
            self.video_writer.release()
            self.video_writer = None

    def get_frame(self) -> bytes:
        """Get the current frame from the streaming output."""
        ret = False
        frame = None

        if self.is_rpi_camera and self.picam2 is not None:
            try:
                frame = self.picam2.capture_array()
                frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
                ret = True
            except Exception:
                pass
        elif self.cap is not None and self.cap.isOpened():
            ret, frame = self.cap.read()
            
        if not ret or frame is None:
            return b''
            
        if self.hflip:
            frame = cv2.flip(frame, 1)
        if self.vflip:
            frame = cv2.flip(frame, 0)
            
        if self.recording and self.video_writer:
            self.video_writer.write(frame)
            
        # Encode to JPEG for streaming
        ret, jpeg = cv2.imencode('.jpg', frame)
        if ret:
            return jpeg.tobytes()
        return b''

    def save_video(self, filename: str, duration: int = 10) -> None:
        """Save a video for the specified duration."""
        self.start_stream(filename)
        start_time = time.time()
        while time.time() - start_time < duration:
            self.get_frame() # Triggers read and write
            time.sleep(0.05)
        self.stop_stream()

    def close(self) -> None:
        """Close the camera."""
        if self.is_rpi_camera and self.picam2:
            self.picam2.stop()
            self.picam2.close()
            self.picam2 = None
        if self.cap and self.cap.isOpened():
            self.cap.release()
            self.cap = None
        if self.video_writer:
            self.video_writer.release()

if __name__ == '__main__':
    print('Program is starting ... ')                    # Print a message indicating the start of the program
    camera = Camera()                                    # Create a Camera instance

    print("View image...")
    camera.start_image(show_preview=True)                # Start the camera preview
    time.sleep(10)                                       # Wait for 10 seconds
    
    print("Capture image...")
    camera.save_image(filename="image.jpg")              # Capture and save an image
    time.sleep(1)                                        # Wait for 1 second

    '''
    print("Stream video...")
    camera.start_stream()                                # Start the video stream
    time.sleep(3)                                        # Stream for 3 seconds
    
    print("Stop video...")
    camera.stop_stream()                                 # Stop the video stream
    time.sleep(1)                                        # Wait for 1 second

    print("Save video...")
    camera.save_video("video.h264", duration=3)          # Save a video for 3 seconds
    time.sleep(1)                                        # Wait for 1 second
    
    print("Close camera...")
    camera.close()                                       # Close the camera
    '''