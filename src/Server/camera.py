import os
os.environ["OPENCV_VIDEOIO_DEBUG"] = "1"
os.environ["OPENCV_LOG_LEVEL"] = "DEBUG"
import cv2
import time
import numpy as np

class Camera:
    def __init__(self, preview_size: tuple = (640, 480), hflip: bool = False, vflip: bool = False, stream_size: tuple = (400, 300)):
        """Initialize the Camera class using OpenCV."""
        self.cap = None
        self.preview_size = preview_size
        self.stream_size = stream_size
        self.hflip = hflip
        self.vflip = vflip
        self.streaming = False
        self.recording = False
        self.video_writer = None

    def _open_camera(self, size: tuple):
        """Internal method to open the camera with a specific resolution."""
        if self.cap is not None and self.cap.isOpened():
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
            # Use the modern libcamera stack via GStreamer
            pipeline = f"libcamerasrc ! video/x-raw, width={size[0]}, height={size[1]}, framerate=15/1 ! videoconvert ! appsink drop=true max-buffers=1"
            self.cap = cv2.VideoCapture(pipeline, cv2.CAP_GSTREAMER)
        else:
            # Local mock: Use the computer's built-in webcam
            self.cap = cv2.VideoCapture(0)

        if not self.cap.isOpened():
            device_name = "libcamerasrc" if is_rpi else "local webcam (index 0)"
            print(f"Error: Could not open video device using {device_name}. Is the camera connected?")
            return

    def start_image(self, show_preview: bool = False) -> None:
        """Start the camera (OpenCV VideoCapture)."""
        self._open_camera(self.preview_size)
        # Note: show_preview is ignored in headless/server context to avoid X11 errors.

    def save_image(self, filename: str) -> dict:
        """Capture and save an image to the specified file."""
        if self.cap is None or not self.cap.isOpened():
            self._open_camera(self.preview_size)
            # If we just cold-started the camera, give the Auto-Exposure time to settle
            time.sleep(2.0)
        
        # Flush the buffer. Because we use 'drop=true max-buffers=1', GStreamer 
        # might be holding onto a dark frame from a few seconds ago. Reading 
        # several frames guarantees we get the freshest, fully-exposed image.
        for _ in range(15):
            self.cap.read()
            
        ret, frame = self.cap.read()
        if ret:
            if self.hflip:
                frame = cv2.flip(frame, 1)
            if self.vflip:
                frame = cv2.flip(frame, 0)
            cv2.imwrite(filename, frame)
            return {"filename": filename}
        else:
            backend = self.cap.getBackendName() if self.cap else "Unknown"
            print(f"Error: Could not read frame. Video Backend: {backend}")
            print(f"Camera State -> Opened: {self.cap.isOpened() if self.cap else False}, Resolution: {self.cap.get(cv2.CAP_PROP_FRAME_WIDTH)}x{self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT)}")
            return None

    def start_stream(self, filename: str = None) -> None:
        """Start the video stream or recording."""
        # Re-open or re-configure for stream size
        if self.cap is not None and self.cap.isOpened():
            self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.stream_size[0])
            self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.stream_size[1])
        else:
            self._open_camera(self.stream_size)

        self.streaming = True
        
        if filename:
            self.recording = True
            # Define the codec and create VideoWriter object
            fourcc = cv2.VideoWriter_fourcc(*'mp4v') 
            w = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            h = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
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
        if self.cap is None or not self.cap.isOpened():
            return b''
            
        ret, frame = self.cap.read()
        if not ret:
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
        if self.cap and self.cap.isOpened():
            self.cap.release()
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