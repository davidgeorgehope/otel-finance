from flask import Flask
import time
import threading

import ml
import alias
import kibana
import slo
import context
import assistant
import integrations
import enroll_elastic_agent
import subprocess
import process_logs


app = Flask(__name__)


def init():
    #assistant.load()
    #context.load()
    truncated_logs_script = 'download-s3/download-logs.sh'
    full_logs_script = 'download-s3/download-logs.sh'

    # Set execute permissions on the shell scripts
    print("Setting execute permissions on shell scripts...")
    subprocess.run(['chmod', '+x', truncated_logs_script], check=True)
    subprocess.run(['chmod', '+x', full_logs_script], check=True)

    print("Running download-truncated-logs.sh...")
    subprocess.run(['sudo', truncated_logs_script, 'truncated'], check=True)

    integrations.load() #nginx, mysql
    enroll_elastic_agent.install_elastic_agent()
    slo.load() 
    ml.load_integration_jobs()
    #update ingest pipeline
    print("Running download-full-logs.sh...")
    subprocess.run(['sudo', full_logs_script, 'full'], check=True)
    
    kibana.load() #dashboards
    


init()
