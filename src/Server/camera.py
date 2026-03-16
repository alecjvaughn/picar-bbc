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
        
        # Restrict to indices 0 and 11 to avoid Pi hardware decoder nodes.
        # Hardware decoders (like index 14 or -1) report as "open" but 
        # will hang indefinitely when we call read().
        for index in [0, 11]:
            self.cap = cv2.VideoCapture(index, cv2.CAP_V4L2)
            if self.cap.isOpened():
                break
                
        if not self.cap.isOpened():
            print("Error: Could not open video device on index 0 or 11. Is the camera connected?")
            return

        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, size[0])
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, size[1])

    def start_image(self, show_preview: bool = False) -> None:
        """Start the camera (OpenCV VideoCapture)."""
        self._open_camera(self.preview_size)
        # Note: show_preview is ignored in headless/server context to avoid X11 errors.

    def save_image(self, filename: str) -> dict:
        """Capture and save an image to the specified file."""
        if self.cap is None or not self.cap.isOpened():
            self._open_camera(self.preview_size)
        
        # Read a few frames to allow auto-exposure to settle
        for _ in range(5):
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
            print("Error: Could not read frame.")
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