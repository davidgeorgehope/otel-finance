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

app = Flask(__name__)


def init():
    #integrations.load()
    #enroll_elastic_agent.install_elastic_agent()
    #kibana.load()
    slo.load()
def maintenance_loop():
    aliases_created = False
    while True:
        if not aliases_created:
            aliases_created = alias.load()
        time.sleep(10)

def start_maintenance_thread():
    thread = threading.Thread(target=maintenance_loop)
    thread.start()

init()
