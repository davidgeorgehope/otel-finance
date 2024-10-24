import os
import requests
import json
import subprocess
import base64

# Set environment variables or replace with your own values
KIBANA_URL = os.environ.get('KIBANA_URL', 'http://localhost:5601')
FLEET_URL = os.environ.get('FLEET_URL', 'http://localhost:8220')
ELASTIC_USER = os.environ.get('ELASTICSEARCH_USER', 'elastic')
ELASTIC_PASSWORD = os.environ.get('ELASTICSEARCH_PASSWORD', 'changeme')
ELASTIC_AGENT_DOWNLOAD_URL = os.environ.get(
    'ELASTIC_AGENT_DOWNLOAD_URL',
    'https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.15.3-linux-x86_64.tar.gz'
)
ELASTIC_AGENT_INSTALL_DIR = os.environ.get('ELASTIC_AGENT_INSTALL_DIR', '/opt/Elastic/Agent')
AGENT_POLICY_NAME = 'Agent policy 1'  # Name from your integration JSON

# Headers
HEADERS = {
    'Content-Type': 'application/json',
    'kbn-xsrf': 'xx'
}

def get_agent_policy_id(policy_name):
    """Retrieve the agent policy ID by name."""
    url = f"{KIBANA_URL}/api/fleet/agent_policies"
    response = requests.get(
        url,
        headers=HEADERS,
        auth=(ELASTIC_USER, ELASTIC_PASSWORD),
        verify=False
    )

    if response.status_code == 200:
        data = response.json()
        items = data.get('items', [])
        for item in items:
            if item.get('name') == policy_name:
                policy_id = item.get('id')
                print(f"Found agent policy '{policy_name}' with ID: {policy_id}")
                return policy_id
        print(f"No agent policy found with name '{policy_name}'")
        return None
    else:
        print(f"Failed to retrieve agent policies: {response.status_code} {response.text}")
        return None

def get_enrollment_api_key_for_policy(policy_id):
    """Retrieve or create an enrollment API key for the given policy ID."""
    url = f"{KIBANA_URL}/api/fleet/enrollment_api_keys"
    params = {'kuery': f'policy_id:"{policy_id}"'}
    response = requests.get(
        url,
        headers=HEADERS,
        auth=(ELASTIC_USER, ELASTIC_PASSWORD),
        params=params,
        verify=False
    )

    if response.status_code == 200:
        data = response.json()
        api_keys = data.get('items', [])
        if api_keys:
            # Return the first enrollment API key for the policy
            enrollment_key = api_keys[0]['api_key']
            print(f"Retrieved enrollment API key for policy {policy_id}: {enrollment_key}")
            return enrollment_key
        else:
            print(f"No enrollment API keys found for policy {policy_id}. Creating one.")
            # Create an enrollment API key for the policy
            return create_enrollment_api_key_for_policy(policy_id)
    else:
        print(f"Failed to retrieve enrollment API keys: {response.status_code} {response.text}")
        return None

def create_enrollment_api_key_for_policy(policy_id):
    """Create a new enrollment API key for the given policy ID."""
    url = f"{KIBANA_URL}/api/fleet/enrollment_api_keys"
    payload = {
        "name": f"Enrollment key for policy {policy_id}",
        "policy_id": policy_id
    }
    response = requests.post(
        url,
        headers=HEADERS,
        auth=(ELASTIC_USER, ELASTIC_PASSWORD),
        json=payload,
        verify=False
    )

    if response.status_code == 200:
        data = response.json()
        enrollment_key = data.get('item', {}).get('api_key')
        print(f"Created enrollment API key for policy {policy_id}: {enrollment_key}")
        return enrollment_key
    else:
        print(f"Failed to create enrollment API key: {response.status_code} {response.text}")
        return None

def download_and_install_elastic_agent(enrollment_token):
    """Download and install the Elastic Agent using the enrollment token."""
    import os
    import subprocess

    # Extract the tarball name from the download URL
    tarball_url = ELASTIC_AGENT_DOWNLOAD_URL
    tarball_name = os.path.basename(tarball_url)

    # Download the Elastic Agent
    download_command = [
        'curl',
        '-L',
        tarball_url,
        '-o',
        tarball_name
    ]
    print("Downloading Elastic Agent...")
    subprocess.run(download_command, check=True)

    # Extract the tarball
    extract_command = [
        'tar',
        'xzf',
        tarball_name
    ]
    print("Extracting Elastic Agent...")
    subprocess.run(extract_command, check=True)

    # Determine the extracted directory name (remove .tar.gz extension)
    extracted_dir = tarball_name.replace('.tar.gz', '')

    # Change to the extracted directory
    os.chdir(extracted_dir)

    # Install the Agent
    print("Installing Elastic Agent...")
    install_command = [
        'sudo',  # Add 'sudo' if root permissions are required
        './elastic-agent',
        'install',
        '--url', FLEET_URL,
        '--enrollment-token', enrollment_token,
        '--insecure'  # Remove this if SSL is properly configured
    ]
    subprocess.run(install_command, check=True)

    # Go back to the original directory
    os.chdir('..')

    # Cleanup
    print("Cleaning up...")
    subprocess.run(['rm', '-rf', tarball_name, extracted_dir], check=True)

def install_elastic_agent():
    """Main function to install the Elastic Agent."""
    # Step 1: Retrieve the agent policy ID
    policy_id = get_agent_policy_id(AGENT_POLICY_NAME)
    if policy_id:
        # Step 2: Get or create the enrollment API key for the policy
        enrollment_token = get_enrollment_api_key_for_policy(policy_id)
        if enrollment_token:
            # Step 3: Download and install the Elastic Agent
            download_and_install_elastic_agent(enrollment_token)
        else:
            print("Enrollment token not found. Exiting.")
    else:
        print("Agent policy not found. Exiting.")

if __name__ == '__main__':
    install_elastic_agent()
