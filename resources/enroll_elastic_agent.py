import os
import requests
import json
import subprocess

# Set environment variables or replace with your own values
KIBANA_URL = os.environ.get('KIBANA_URL', 'http://localhost:5601')
KIBANA_USER = os.environ.get('KIBANA_USER', os.environ['ELASTICSEARCH_USER'])
KIBANA_PASSWORD = os.environ.get('KIBANA_PASSWORD', os.environ['ELASTICSEARCH_PASSWORD'])
ELASTIC_AGENT_DOWNLOAD_URL = os.environ.get('ELASTIC_AGENT_DOWNLOAD_URL', 'https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.15.2-linux-x86_64.tar.gz')
ELASTIC_AGENT_INSTALL_DIR = os.environ.get('ELASTIC_AGENT_INSTALL_DIR', '/opt/Elastic/Agent')

HEADERS = {
    'Content-Type': 'application/json',
    'kbn-xsrf': 'xx'
}

def get_enrollment_api_keys():
    url = f"{KIBANA_URL}/api/fleet/enrollment_api_keys"
    response = requests.get(url, headers=HEADERS, auth=(KIBANA_USER, KIBANA_PASSWORD), verify=False)

    if response.status_code == 200:
        data = response.json()
        api_keys = data.get('items', [])
        if api_keys:
            # Return the first enrollment API key
            enrollment_key = api_keys[0]['api_key']
            print(f"Retrieved enrollment API key: {enrollment_key}")
            return enrollment_key
        else:
            print("No enrollment API keys found.")
            return None
    else:
        print(f"Failed to retrieve enrollment API keys: {response.status_code} {response.text}")
        return None

def install_elastic_agent(enrollment_token):
    # Download the Elastic Agent
    agent_tarball = 'elastic-agent.tar.gz'
    download_command = [
        'curl',
        '-L',
        ELASTIC_AGENT_DOWNLOAD_URL,
        '-o',
        agent_tarball
    ]
    print("Downloading Elastic Agent...")
    subprocess.run(download_command, check=True)

    # Extract the tarball
    extract_command = [
        'tar',
        '-xzf',
        agent_tarball
    ]
    print("Extracting Elastic Agent...")
    subprocess.run(extract_command, check=True)

    # Install the Agent
    print("Installing Elastic Agent...")
    install_command = [
        './elastic-agent/install.sh',
        '--url', KIBANA_URL,
        '--enrollment-token', enrollment_token,
        '--insecure'  # Add this if SSL is not properly configured; remove if not needed
    ]
    subprocess.run(install_command, check=True)

if __name__ == "__main__":
    enrollment_token = get_enrollment_api_keys()
    if enrollment_token:
        install_elastic_agent(enrollment_token)
    else:
        print("Enrollment token not found. Exiting.")
