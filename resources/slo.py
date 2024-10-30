import requests
import os
import json

TIMEOUT = 10

SLO_RESOURCES_PATH = 'slo'

def load():
    new_slo_ids = []
    slo_files = [file for file in os.listdir(SLO_RESOURCES_PATH) if file.endswith(".json")]

    for file in slo_files:
        with open(os.path.join(SLO_RESOURCES_PATH, file), "r", encoding='utf8') as f:
            body = f.read()
            resp = requests.post(
                f"{os.environ['KIBANA_URL']}/api/observability/slos",
                data=body,
                timeout=TIMEOUT,
                auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
                headers={"kbn-xsrf": "reporting", "Content-Type": "application/json"}
            )
            resp_json = resp.json()
            print(resp_json)
            new_slo_id = resp_json['id']
            new_slo_ids.append(new_slo_id)

    # Now update the dashboard file with new SLO IDs
    dashboard_path = 'resources/kibana/dashboards.ndjson'
    with open(dashboard_path, 'r', encoding='utf8') as f:
        dashboard_lines = f.readlines()

    updated_lines = []
    slo_id_index = 0

    for line in dashboard_lines:
        data = json.loads(line)
        if data.get('attributes') and data['attributes'].get('panelsJSON'):
            panels = json.loads(data['attributes']['panelsJSON'])
            for panel in panels:
                embeddableConfig = panel.get('embeddableConfig', {})
                if 'sloId' in embeddableConfig:
                    if slo_id_index < len(new_slo_ids):
                        old_slo_id = embeddableConfig['sloId']
                        new_slo_id = new_slo_ids[slo_id_index]
                        embeddableConfig['sloId'] = new_slo_id
                        slo_id_index += 1
                        print(f"Replaced SLO ID {old_slo_id} with {new_slo_id}")
                    else:
                        print("Warning: Not enough new SLO IDs to replace all existing ones")
            # Update the panelsJSON with the modified panels
            data['attributes']['panelsJSON'] = json.dumps(panels)

        updated_line = json.dumps(data)
        updated_lines.append(updated_line)

    # Write back the updated dashboard
    with open(dashboard_path, 'w', encoding='utf8') as f:
        f.writelines(line + '\n' for line in updated_lines)
