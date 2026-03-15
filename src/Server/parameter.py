# Import necessary modules
import os
import json
import subprocess

class ParameterManager:
    # Define the default parameter file name
    PARAM_FILE = 'params.json'

    def __init__(self):
        # Initialize the file path to the default parameter file
        self.deal_with_param()

    def file_exists(self, file_path: str = PARAM_FILE) -> bool:
        """Check if the specified file exists."""
        return os.path.exists(file_path)

    def validate_params(self, file_path: str = PARAM_FILE) -> bool:
        """Validate that the parameter file exists and contains valid parameters."""
        if not self.file_exists(file_path):
            return False
        try:
            with open(file_path, 'r') as file:
                params = json.load(file)
                # Check if required parameters are present and valid
                required_params = {
                    'Connect_Version': [1, 2],
                    'Pcb_Version': [1, 2],
                    'Pi_Version': [1, 2]
                }
                for param, valid_values in required_params.items():
                    if param not in params or params[param] not in valid_values:
                        return False
                return True
        except json.JSONDecodeError:
            print("Error decoding JSON file.")
            return False
        except Exception as e:
            print(f"Error reading file: {e}")
            return False

    def get_param(self, param_name: str, file_path: str = PARAM_FILE) -> any:
        """Get the value of a specified parameter from the parameter file."""
        if self.validate_params(file_path):
            with open(file_path, 'r') as file:
                params = json.load(file)
                return params.get(param_name)
        return None

    def set_param(self, param_name: str, value: any, file_path: str = PARAM_FILE) -> None:
        """Set the value of a specified parameter in the parameter file."""
        params = {}
        if self.file_exists(file_path):
            with open(file_path, 'r') as file:
                params = json.load(file)
        params[param_name] = value
        with open(file_path, 'w') as file:
            json.dump(params, file, indent=4)

    def delete_param_file(self, file_path: str = PARAM_FILE) -> None:
        """Delete the specified parameter file."""
        if self.file_exists(file_path):
            os.remove(file_path)
            print(f"Deleted {file_path}")
        else:
            print(f"File {file_path} does not exist")

    def create_param_file(self, file_path: str = PARAM_FILE) -> None:
        """Create a parameter file and set default parameters."""
        print("Creating default parameter file...")
        default_params = {
            'Connect_Version': 2,
            'Pcb_Version': 1,
            'Pi_Version': self.get_raspberry_pi_version()
        }
        with open(file_path, 'w') as file:
            json.dump(default_params, file, indent=4)

    def get_raspberry_pi_version(self) -> int:
        """Get the version of the Raspberry Pi."""
        try:
            result = subprocess.run(['cat', '/sys/firmware/devicetree/base/model'], capture_output=True, text=True)
            if result.returncode == 0:
                model = result.stdout.strip()
                if "Raspberry Pi 5" in model:
                    return 2
                else:
                    return 1
            else:
                print("Failed to get Raspberry Pi model information.")
                return 1
        except Exception as e:
            print(f"Error getting Raspberry Pi version: {e}")
            return 1

    def deal_with_param(self) -> None:
        """
        Checks for a valid parameter file. If it's missing or invalid,
        it creates a new one with safe defaults. This is non-interactive
        to support headless/Docker operation.
        """
        if not self.file_exists() or not self.validate_params():
            print(f"WARNING: Parameter file '{self.PARAM_FILE}' not found or invalid.")
            self.create_param_file()
        else:
            print(f"Using existing parameter file: '{self.PARAM_FILE}'")

    def get_connect_version(self) -> int:
        """Get the Connect version from the parameter file."""
        return self.get_param('Connect_Version')

    def get_pcb_version(self) -> int:
        """Get the PCB version from the parameter file."""
        return self.get_param('Pcb_Version')

    def get_pi_version(self) -> int:
        """Get the Raspberry Pi version from the parameter file."""
        return self.get_param('Pi_Version')