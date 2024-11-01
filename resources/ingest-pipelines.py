import glob
import json
import os
import requests

# Replace these with your actual Elasticsearch URL and headers
ELASTICSEARCH_URL = os.environ['ELASTICSEARCH_URL']
HEADERS = {'Content-Type': 'application/json'}

def load():
    """Process and create ingest pipelines from JSON files in the 'ingest-pipelines' directory."""
    pipeline_files = glob.glob('ingest-pipelines/*.json')

    for pipeline_file in pipeline_files:
        # Load the pipeline configuration from the JSON file
        with open(pipeline_file, 'r') as config_file:
            pipeline_config = json.load(config_file)

        # Extract pipeline name from the config or filename
        pipeline_name = pipeline_config.get('name')
        if not pipeline_name:
            # Fall back to filename without extension if name not in config
            pipeline_name = os.path.splitext(os.path.basename(pipeline_file))[0]

        # Create pipeline
        pipeline_url = f"{ELASTICSEARCH_URL}/_ingest/pipeline/{pipeline_name}"

        response = requests.put(
            pipeline_url,
            headers={'Content-Type': 'application/json'},
            auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD']),
            json=pipeline_config
        )

        if response.status_code not in [200, 201]:
            print(f"Failed to create pipeline {pipeline_name}: {response.status_code} - {response.text}")
            continue

        print(f"Pipeline {pipeline_name} from {pipeline_file} created successfully.")