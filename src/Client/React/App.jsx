import React, { useState, useEffect, useRef } from 'react';
import './App.css';

function App() {
  const [ip, setIp] = useState('127.0.0.1:5001');
  const [servoX, setServoX] = useState(90);
  const [servoY, setServoY] = useState(90);
  const [ledMode, setLedMode] = useState(0);
  const [buzzerState, setBuzzerState] = useState(0);
  const [videoOpen, setVideoOpen] = useState(false);
  const [streamKey, setStreamKey] = useState(Date.now());
  const [debugOpen, setDebugOpen] = useState(false);
  const [logs, setLogs] = useState([]);
  const logEndRef = useRef(null);

  // Stream logs from the backend using Server-Sent Events
  useEffect(() => {
    if (!debugOpen) return;
    const eventSource = new EventSource(`http://${ip}/api/logs_stream`);
    eventSource.onmessage = (e) => {
      setLogs((prev) => {
        const newLogs = [...prev, e.data];
        // Keep only the last 100 entries to prevent memory bloat
        return newLogs.length > 100 ? newLogs.slice(newLogs.length - 100) : newLogs;
      });
    };
    return () => eventSource.close();
  }, [debugOpen, ip]);

  // Auto-scroll logs to the bottom
  useEffect(() => {
    if (debugOpen && logEndRef.current) {
      logEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs, debugOpen]);

  // Generic API Caller for FastAPI
  const sendCommand = async (endpoint, payload) => {
    try {
      const response = await fetch(`http://${ip}${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      if (!response.ok) throw new Error('Network response was not ok');
    } catch (error) {
      console.error(`Failed to execute ${endpoint}:`, error);
    }
  };

  // --- Movement Controls ---
  const handleMove = (action) => sendCommand('/api/move', { action });
  const handleStop = () => sendCommand('/api/move', { action: 'stop' });

  // Helper to attach pointer events (handles both mouse and touch correctly)
  const moveProps = (action) => ({
    onPointerDown: (e) => { e.currentTarget.setPointerCapture(e.pointerId); handleMove(action); },
    onPointerUp: (e) => { e.currentTarget.releasePointerCapture(e.pointerId); handleStop(); },
    onContextMenu: (e) => e.preventDefault(), // Prevents right-click menu on long press
  });

  // --- Servo Controls ---
  const handleServoX = (e) => {
    const val = parseInt(e.target.value);
    setServoX(val);
    sendCommand('/api/servo', { id: 0, angle: val });
  };

  const handleServoY = (e) => {
    const val = parseInt(e.target.value);
    setServoY(val);
    sendCommand('/api/servo', { id: 1, angle: val });
  };

  const centerServos = () => {
    setServoX(90);
    setServoY(90);
    sendCommand('/api/servo', { id: 0, angle: 90 });
    sendCommand('/api/servo', { id: 1, angle: 90 });
  };

  // --- Peripherals ---
  const toggleBuzzer = () => {
    const newState = buzzerState === 0 ? 1 : 0;
    setBuzzerState(newState);
    sendCommand('/api/buzzer', { state: newState });
  };

  const handleLedMode = (mode) => {
    setLedMode(mode);
    sendCommand('/api/led', { mode: mode });
  };

  const setCarMode = (mode) => {
    sendCommand('/api/car_mode', { mode });
  };

  return (
    <div className="dashboard">
      <h1>PiCar Web Dashboard</h1>
      
      <div className="header-controls">
        <label>API IP: </label>
        <input 
          type="text" 
          value={ip} 
          onChange={(e) => setIp(e.target.value)} 
          placeholder="192.168.x.x:5001"
        />
        <button onClick={() => setDebugOpen(!debugOpen)} style={{marginLeft: '10px', background: debugOpen ? '#00BB9E' : ''}}>
          {debugOpen ? 'Hide Debug' : 'Show Debug'}
        </button>
      </div>

      {/* LEFT COLUMN: Camera & Servos */}
      <div className="panel">
        <h2>Camera Feed</h2>
        <div className="video-feed">
          {videoOpen ? (
            <img src={`http://${ip}/api/video_feed?t=${streamKey}`} alt="Stream" style={{width: '100%', height: '100%', objectFit: 'cover'}}/>
          ) : (
            <span style={{color: '#666'}}>Video Closed</span>
          )}
        </div>
        <br/>
        <button onClick={() => {
          if (!videoOpen) setStreamKey(Date.now());
          setVideoOpen(!videoOpen);
        }}>
          {videoOpen ? 'Close Video' : 'Open Video'}
        </button>

        <h2 style={{marginTop: '20px'}}>Servos</h2>
        <div className="servo-controls">
          <div className="slider-group">
            <span>Pan (X): {servoX}°</span>
            <input type="range" min="0" max="180" value={servoX} onChange={handleServoX} />
          </div>
          <div className="slider-group">
            <span>Tilt (Y): {servoY}°</span>
            <input type="range" min="80" max="180" value={servoY} onChange={handleServoY} />
          </div>
          <button onClick={centerServos}>Center Camera</button>
        </div>
      </div>

      {/* RIGHT COLUMN: Movement & Controls */}
      <div className="panel">
        <h2>Movement</h2>
        <div className="d-pad">
          <div></div>
          <button {...moveProps('forward')}>W</button>
          <div></div>
          <button {...moveProps('left')}>A</button>
          <button {...moveProps('backward')}>S</button>
          <button {...moveProps('right')}>D</button>
        </div>

        <h2 style={{marginTop: '20px'}}>Peripherals</h2>
        <div className="modes">
          <button 
            onClick={toggleBuzzer} 
            style={{ background: buzzerState ? '#ff4444' : '' }}
          >
            {buzzerState ? 'Stop Buzzer' : 'Sound Buzzer'}
          </button>
          <button onClick={() => sendCommand('/api/buzzer', { state: 0 })}>Ultrasonic (TBD)</button>
        </div>

        <h2 style={{marginTop: '20px'}}>LED Modes</h2>
        <div className="modes">
          <button 
            style={{ borderLeft: ledMode === 0 ? '2px solid #00BB9E' : '' }}
            onClick={() => handleLedMode(0)}>Off</button>
          <button 
            style={{ borderLeft: ledMode === 1 ? '2px solid #00BB9E' : '' }}
            onClick={() => handleLedMode(1)}>Manual</button>
          <button 
            style={{ borderLeft: ledMode === 2 ? '2px solid #00BB9E' : '' }}
            onClick={() => handleLedMode(2)}>Following</button>
          <button 
            style={{ borderLeft: ledMode === 3 ? '2px solid #00BB9E' : '' }}
            onClick={() => handleLedMode(3)}>Blink</button>
          <button 
            style={{ borderLeft: ledMode === 4 ? '2px solid #00BB9E' : '' }}
            onClick={() => handleLedMode(4)}>Rainbow</button>
        </div>

        <h2 style={{marginTop: '20px'}}>Car Modes</h2>
        <div className="modes">
          <button onClick={() => setCarMode('manual')}>M-Free</button>
          <button onClick={() => setCarMode('light')}>M-Light</button>
          <button onClick={() => setCarMode('ultrasonic')}>M-Sonic</button>
          <button onClick={() => setCarMode('infrared')}>M-Line</button>
        </div>
      </div>

      {/* Bottom Panel: Debug View */}
      {debugOpen && (
        <div className="panel debug-panel">
          <h2>API Debug Logs</h2>
          <div className="log-window">
            {logs.map((log, i) => (
              <div key={i} className="log-entry">{log}</div>
            ))}
            <div ref={logEndRef} />
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
