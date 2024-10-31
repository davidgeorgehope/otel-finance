from elasticsearch import Elasticsearch
import os
from pathlib import Path
import json
import time

def load_trained(*, replace=True):
    with Elasticsearch(os.environ['ELASTICSEARCH_URL'], basic_auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD'])) as client:

        inference_processors = []

        for file in os.listdir("ml/trained/job"):
            
            with open(os.path.join("ml/trained/job", file), 'r') as job:
                filename = Path(file).stem
                print("preparing trained ml job {filename}")

                if replace:
                    try:
                        print(f"looking for old pipelines ml-inference-{filename}*")
                        result = client.ingest.get_pipeline(id=f"ml-inference-{filename}*")
                        for _, pipeline_id in enumerate(result.keys()):
                                print(f"deleting old pipeline {pipeline_id}")
                                res = client.ingest.delete_pipeline(id=pipeline_id)
                    except Exception as inst:
                        print(f"unable to delete old pipelines ml-inference-{filename}*: {inst}")
                    
                    try:
                        print(f"looking for old trained models {filename}*")
                        result = client.ml.get_trained_models(model_id=f"{filename}*")
                        for trained_model_config in result['trained_model_configs']:
                            print(f"deleting old trained model {filename}*")
                            res = client.ml.delete_trained_model(model_id=trained_model_config['model_id'], force=True)
                    except Exception as inst:
                        print(f"unable to delete old trained models {filename}*: {inst}")
                              
                    try:
                        print(f"deleting old data frame analytics {filename}*")
                        result = client.ml.delete_data_frame_analytics(id=filename, force=True)
                    except Exception as inst:
                        print(f"unable to delete old data frame analytics {filename}*: {inst}")
                    
                    try:
                        print(f"deleting old index {filename}")
                        result = client.indices.delete(index=filename)
                    except Exception as inst:
                        print(f"unable to delete old index {filename}: {inst}")

                json_job = json.load(job)

                try:
                    print("create trained ml job {filename}")
                    client.ml.put_data_frame_analytics(id=filename, body=json_job)
                except Exception as inst:
                    print(f"create trained ml job {filename}: {inst}")

                try:
                    print(f"start data frame analytics {filename}")
                    res = client.ml.start_data_frame_analytics(id=filename)
                    print(res)
                except Exception as inst:
                    print(f"started data frame analytics {filename}: {inst}")
                
                for _ in range(5):
                    time.sleep(2)
                    
                    try:
                        print(f"get trained models {filename}")
                        result = client.ml.get_trained_models(model_id=f"{filename}*")
                        if len(result['trained_model_configs']) == 0:
                            continue
                        
                        model = result['trained_model_configs'][0]
                            
                        with open(os.path.join("ml/trained/pipeline", file), 'r') as pipeline:
                            print("preparing pipeline {filename}")
                            
                            raw_pipeline = pipeline.read()
                            raw_pipeline = raw_pipeline.replace("{{ MODEL_ID }}", model['model_id'])
                            json_pipeline = json.loads(raw_pipeline)
                            
                            print("create pipeline {filename}")
                            res = client.ingest.put_pipeline(id=f"ml-inference-{model['model_id']}", body=json_pipeline)
                            
                            inference_processors.append({
                                        "pipeline": {
                                            "name": f"ml-inference-{model['model_id']}",
                                            "ignore_missing_pipeline": True,
                                            "ignore_failure": True
                                        }
                                    })
                        break
                    except Exception as inst:
                        print(f"started data frame analytics {filename}: {inst}")
                        
                        
        body = {
            "processors": inference_processors
        }
        print("setting apm pipelines {body}")
        res = client.ingest.put_pipeline(id="traces-apm@custom", body=body)


def load_anomaly(*, replace=False):
    with Elasticsearch(os.environ['ELASTICSEARCH_URL'], basic_auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD'])) as client:

        for file in os.listdir("ml/anomaly/job"):
            with open(os.path.join("ml/anomaly/job", file), 'r') as job:
                filename = Path(file).stem
                json_job = json.load(job)

                if replace:
                    client.ml.stop_datafeed(datafeed_id=json_job['datafeed_config']['datafeed_id'])
                    client.ml.close_job(job_id=filename)
                    client.ml.delete_job(job_id=filename, delete_user_annotations=True)

                try:
                    client.ml.put_job(job_id=filename, body=json_job)
                except Exception as inst:
                    print(inst)
                    
                try:
                    client.ml.open_job(job_id=filename)
                except Exception as inst:
                    print(inst)
  
                try:
                    client.ml.start_datafeed(datafeed_id=json_job['datafeed_config']['datafeed_id'])
                except Exception as inst:
                    print(inst)

def load_integration_jobs(config_path="ml-integrations/config.json", replace=False):

    with open(config_path, 'r') as f:
        config = json.load(f)

    attributes = config.get('attributes', {})
    jobs = attributes.get('jobs', [])
    datafeeds = attributes.get('datafeeds', [])
    query = attributes.get('query', {})
    default_index_pattern = attributes.get('defaultIndexPattern', 'logs-*')

    es = Elasticsearch(
        os.environ['ELASTICSEARCH_URL'],
        basic_auth=(os.environ['ELASTICSEARCH_USER'], os.environ['ELASTICSEARCH_PASSWORD'])
    )

    # Create ML Jobs
    for job_entry in jobs:
        job_id = job_entry['id']
        job_config = job_entry['config']
        if replace:
            try:
                print(f"Deleting existing job: {job_id}")
                es.ml.stop_datafeed(datafeed_id=f"datafeed-{job_id}", force=True)
                es.ml.close_job(job_id=job_id, force=True)
                es.ml.delete_job(job_id=job_id, force=True)
            except Exception as e:
                print(f"Could not delete job {job_id}: {e}")

        try:
            print(f"Creating job: {job_id}")
            es.ml.put_job(job_id=job_id, body=job_config)
            es.ml.open_job(job_id=job_id)
        except Exception as e:
            print(f"Error creating job {job_id}: {e}")

    # Create Datafeeds
    for datafeed_entry in datafeeds:
        datafeed_id = datafeed_entry.get('id')
        datafeed_config = datafeed_entry.get('config')
        datafeed_config['indices'] = [default_index_pattern]
        if replace:
            try:
                print(f"Deleting existing datafeed: {datafeed_id}")
                es.ml.stop_datafeed(datafeed_id=datafeed_id, force=True)
                es.ml.delete_datafeed(datafeed_id=datafeed_id, force=True)
            except Exception as e:
                print(f"Could not delete datafeed {datafeed_id}: {e}")

        try:
            print(f"Creating datafeed: {datafeed_id}")
            es.ml.put_datafeed(datafeed_id=datafeed_id, body=datafeed_config)
            es.ml.start_datafeed(datafeed_id=datafeed_id)
        except Exception as e:
            print(f"Error creating datafeed {datafeed_id}: {e}")

    es.close()
