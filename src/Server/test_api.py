import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

# Import your FastAPI app
from WebAPI import app

client = TestClient(app)

def test_status_endpoint():
    """Test that the status endpoint returns 200 and expected format."""
    # We can mock the socket connection inside the status endpoint to pretend the hardware is online
    with patch('socket.socket') as mock_socket:
        response = client.get("/api/status")
        assert response.status_code == 200
        data = response.json()
        assert data["api"] == "online"
        assert "backend" in data

@patch('WebAPI.send_command')
def test_move_forward(mock_send_command):
    """Test that the /api/move endpoint translates 'forward' into the correct raw string."""
    # Force the mock send_command to return True (success)
    mock_send_command.return_value = True
    
    response = client.post("/api/move", json={"action": "forward"})
    
    assert response.status_code == 200
    assert response.json() == {"status": "success", "action": "forward"}
    
    # CRITICAL TDD ASSERTION: Did the API formulate the correct hardware string?
    mock_send_command.assert_called_once_with("CMD_MOTOR#1500#1500#1500#1500\n")

def test_move_invalid_action():
    """Test that invalid movements get rejected by Pydantic/FastAPI logic."""
    response = client.post("/api/move", json={"action": "fly"})
    # Our API should return a 400 Bad Request for actions not in our allowed list
    assert response.status_code == 400