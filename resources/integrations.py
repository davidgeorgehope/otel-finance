import os
import requests
import json

KIBANA_URL = os.environ['KIBANA_URL']
TIMEOUT = 10

HEADERS = {
    'Content-Type': 'application/json',
    'kbn-xsrf': 'true'
}

def load():
    # Import dashboards and saved objects (existing code)
    # Load the Nginx integration configuration from the JSON file
    with open('resources/nginx_integration.json', 'r') as config_file:
        config = json.load(config_file)

    # Create agent policy
    agent_policy = config.get('agent_policy')
    agent_policy_url = f"{KIBANA_URL}/api/fleet/agent_policies?sys_monitoring=true"
    agent_policy_payload = agent_policy

    response = requests.post(agent_policy_url, headers=HEADERS,  auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']), json=agent_policy_payload)
    
    if response.status_code != 200 and response.status_code != 200:
        print(f"Failed to create agent policy: {response.status_code} - {response.text}")
        return

    agent_policy_id = response.json()['item']['id']
    print(f"Created agent policy with ID: {agent_policy_id}")

    # Create package policy
    package_policy = config.get('package_policy')
    package_policy_payload = package_policy.copy()
    package_policy_payload['policy_id'] = agent_policy_id  # Assign the agent policy ID
    package_policy_url = f"{KIBANA_URL}/api/fleet/package_policies"

    response = requests.post(package_policy_url, headers=HEADERS,  auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']), json=package_policy_payload)

    if response.status_code != 200 and response.status_code != 200:
        print(f"Failed to create package policy: {response.status_code} - {response.text}")
        return

    print("Nginx integration installed successfully.")
