import { render, screen, fireEvent } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import App from './App';

// Mock the global fetch function so we can intercept API calls
global.fetch = vi.fn();

// JSDOM doesn't implement pointer capture methods, so we mock them to prevent errors
window.HTMLElement.prototype.setPointerCapture = vi.fn();
window.HTMLElement.prototype.releasePointerCapture = vi.fn();
window.HTMLElement.prototype.scrollIntoView = vi.fn();

describe('PiCar Web Dashboard', () => {
  beforeEach(() => {
    // Clear out our fetch mock before each test
    vi.clearAllMocks();
    // Default mock response for successful fetch
    global.fetch.mockResolvedValue({ ok: true });
  });

  it('centers the camera servos when the button is clicked', () => {
    render(<App />);
    
    const centerBtn = screen.getByText('Center Camera');
    fireEvent.click(centerBtn);

    // Expect fetch to be called twice (X to 90, Y to 90)
    expect(global.fetch).toHaveBeenCalledTimes(2);
    expect(global.fetch).toHaveBeenCalledWith('http://127.0.0.1:5001/api/servo', expect.objectContaining({
      body: JSON.stringify({ id: 0, angle: 90 })
    }));
    expect(global.fetch).toHaveBeenCalledWith('http://127.0.0.1:5001/api/servo', expect.objectContaining({
      body: JSON.stringify({ id: 1, angle: 90 })
    }));
  });

  it('sends the forward command when W is held down', () => {
    render(<App />);
    
    const forwardBtn = screen.getByText('W');
    
    // Simulate pointer down (touch/mouse press)
    fireEvent.pointerDown(forwardBtn, { pointerId: 1 });

    expect(global.fetch).toHaveBeenCalledWith('http://127.0.0.1:5001/api/move', expect.objectContaining({
      method: 'POST',
      body: JSON.stringify({ action: 'forward' })
    }));
  });
});