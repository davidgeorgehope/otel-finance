import os
import requests
import json
import glob

KIBANA_URL = os.environ['KIBANA_URL']
TIMEOUT = 10

HEADERS = {
    'Content-Type': 'application/json',
    'kbn-xsrf': 'true'
}

def get_agent_policy_id(policy_name):
    """Retrieve the agent policy ID by name."""
    url = f"{KIBANA_URL}/api/fleet/agent_policies"
    params = {'kuery': f'name:"{policy_name}"'}
    response = requests.get(
        url,
        headers=HEADERS,
        auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
        params=params,
        verify=False  # Set to True in production
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

def create_agent_policies():
    """Create agent policies from JSON files in the 'agent_policies' directory."""
    agent_policy_files = glob.glob('agent_policies/*.json')
    for agent_policy_file in agent_policy_files:
        with open(agent_policy_file, 'r') as file:
            agent_policy_config = json.load(file)

        agent_policy_name = agent_policy_config.get('name')
        if not agent_policy_name:
            print(f"No 'name' field in {agent_policy_file}")
            continue

        agent_policy_id = get_agent_policy_id(agent_policy_name)
        if agent_policy_id:
            print(f"Agent policy '{agent_policy_name}' already exists with ID: {agent_policy_id}")
            continue

        # Create a new agent policy
        agent_policy_url = f"{KIBANA_URL}/api/fleet/agent_policies?sys_monitoring=true"
        response = requests.post(
            agent_policy_url,
            headers=HEADERS,
            auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
            json=agent_policy_config
        )

        if response.status_code != 200:
            print(f"Failed to create agent policy: {response.status_code} - {response.text}")
            continue

        agent_policy_id = response.json()['item']['id']
        print(f"Created agent policy '{agent_policy_name}' with ID: {agent_policy_id}")

def load():
    create_agent_policies()
    """Process and create package policies from JSON files in the 'integrations' directory."""
    integration_files = glob.glob('integrations/*.json')

    for integration_file in integration_files:
        # Load the package policy configuration from the JSON file
        with open(integration_file, 'r') as config_file:
            config = json.load(config_file)

        # Get agent policy name from the config
        agent_policy_name = config.get('agent_policy_name')
        if not agent_policy_name:
            print(f"No 'agent_policy_name' specified in {integration_file}")
            continue

        # Retrieve the agent policy ID
        agent_policy_id = get_agent_policy_id(agent_policy_name)
        if not agent_policy_id:
            print(f"Agent policy '{agent_policy_name}' not found for {integration_file}")
            continue

        # Create package policy
        package_policy = config.get('package_policy')
        if not package_policy:
            print(f"No 'package_policy' specified in {integration_file}")
            continue

        package_policy_payload = package_policy.copy()
        package_policy_payload['policy_id'] = agent_policy_id  # Assign the agent policy ID
        package_policy_url = f"{KIBANA_URL}/api/fleet/package_policies"

        response = requests.post(
            package_policy_url,
            headers=HEADERS,
            auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
            json=package_policy_payload
        )

        if response.status_code != 200:
            print(f"Failed to create package policy: {response.status_code} - {response.text}")
            continue

        print(f"Integration from {integration_file} installed successfully.")
