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


app = Flask(__name__)


def init():
    #assistant.load()
    #context.load()
    full_logs_script = 'download-s3/download-logs.sh'

    # Set execute permissions on the shell scripts
    print("Setting execute permissions on shell scripts...")
    subprocess.run(['chmod', '+x', full_logs_script], check=True)

    print("Running download-full-logs.sh...")
    subprocess.run(['sudo', full_logs_script, 'full', '--no-timestamp-processing'], check=True)

    integrations.load() #nginx, mysql
    #update ingest pipeline

    enroll_elastic_agent.install_elastic_agent()
    slo.load() 
    time.sleep(180)
    ml.load_integration_jobs()
    kibana.load() #dashboards
    


init()
