import sys
import uvicorn
import re
import os, socket
import argparse
import fibapi
import json
import subprocess
from fibenv import FibaroEnvironment

app = fibapi.app

# main startup
if __name__ == "__main__":
    global config
    print(f"Python version {sys.version}",file=sys.stderr)
    print(f"Platform is {sys.platform}",file=sys.stderr)
    hostname=socket.gethostname() or ''
    print(f"Host name {hostname}",file=sys.stderr)
    hostIP = socket.gethostbyname(hostname)
    print(f"Host ip {hostIP}",file=sys.stderr)
    version = "0.55"
    parser = argparse.ArgumentParser(
                    prog='fibemu',
                    description='QA/HC3 emulator for HC3',
                    epilog='jan@gabrielsson.com')

    try:
        with open(os.path.expanduser('~') + '/.fibemu.json') as f:
            config = json.load(f)
    except Exception:
        config = {}

    parser.add_argument('-f', "--file", help='initial QA to load')
    parser.add_argument('-f2', "--file2", help='second QA to load')
    parser.add_argument('-f3', "--file3", help='third QA to load')
    parser.add_argument('-l', "--local", help='run with no HC3 connection', action='store_true')
    parser.add_argument('-h3', "--host", help='HC3 host name or IP')
    parser.add_argument('-u', "--user", help='HC3 user name')
    parser.add_argument('-pwd', "--password", help='HC3 user password')
    parser.add_argument('-p', "--port", help='HC3 port', default=80, type=int)
    parser.add_argument('-i', '--init', help='init file')
    parser.add_argument('-e', '--emulator', help='emulator file', default='emu.lua')
    parser.add_argument('-b', "--stop", help='debuger break on load file', action='store_true')
    parser.add_argument('-nw', '--noweb', help='no web api', action='store_true')
    parser.add_argument('-ng', "--nogreet", help='No emulator greet message', action='store_true')
    parser.add_argument('-wp', '--wport', default=5004, help='port for web/api interface', type=int)
    parser.add_argument('-wh', '--whost', default='0.0.0.0', help='host for webserver')
    parser.add_argument('-wlv', '--web_log_level', default='warning', help='log level for webserver',choices=['debug', 'info', 'trace', 'warning', 'error', 'critical'])
    parser.add_argument('-extra', '--extra', nargs='*', help='extra arguments for QA', default=[]) 

    args = parser.parse_args()

    path = os.path
    configPaths = ["config.json",args.file and path.join(path.dirname(args.file) or "","config.json")]
    for c in configPaths:
        if path.exists(c):
            with open(c) as f:
                config_d = json.load(f)
                for key, value in config_d.items():
                    config[key] = value
                print(f"Loaded config from {c}",file=sys.stderr)
                ##print(config_d,file=sys.stderr)
            break
    

    config['local'] = args.local
    config['user'] = args.user or config.get('user') or os.environ.get('HC3_USER')
    config['password'] = args.password or config.get('password') or os.environ.get('HC3_PASSWORD')
    config['host'] = args.host or config.get('host') or os.environ.get('HC3_HOST')
    config['port'] = args.port or config.get('port') or os.environ.get('HC3_PORT')
    config['wport'] = args.wport or config.get('wport') or os.environ.get('FIBEMU_PORT')
    config['whost'] = args.whost or config.get('whost') or os.environ.get('FIBEMU_HOST')
    config['wlog'] = args.web_log_level
    config['emulator'] = args.emulator
    config['init'] = args.init
    config['break'] = args.stop
    config['file1'] = args.file or "qa2.lua"
    config['file2'] = args.file2 or None
    config['file3'] = args.file3 or None
    config['version'] = version
    config['server'] = args.noweb
    config['path'] = ".vscode/emufiles/"
    config['argv'] = sys.argv
    config['extra'] = args.extra
    config['nogreet'] = args.nogreet
    config['hostIP'] = hostIP
    config['hostName']= hostname  

    config['apiURL'] =  f"http://localhost:{config['wport']}/api"
    config['apiDocURL'] =  f"http://localhost:{config['wport']}/docs"
    config['webURL'] =  f"http://localhost:{config['wport']}/"
    
    if not config['local'] and  (not config['user'] or not config['password'] or not config['host']):
        print("Missing HC3 connection info for non-local run",file=sys.stderr)
        sys.exit(1)

    def run(self, cmd):
        completed = subprocess.run(["powershell", "-Command", cmd], capture_output=False)
        return completed

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        stat = s.connect_ex(('localhost', config['wport']))
        print(f"Web server port {config['wport']} status {stat}",file=sys.stderr)
        # if stat == 0:
        #     print("Port already in use",file=sys.stderr)
        #     if sys.platform == "darwin":
        #         os.system(f"kill -9 $(lsof -ti :{config['wport']})")
        #     elif sys.platform == "win32":
        #         run(f"Stop-Process -Id (Get-NetTCPConnection -LocalPort {config['wport']}).OwningProcess -Force")

    f = FibaroEnvironment(config)
    fibapi.fibenv['fe'] = f
    f.run()
    if not args.noweb:
        uvicorn.run("__init__:app", host=config['whost'], port=config['wport'], log_level=config['wlog'])
    else:
        print("Web server disabled",file=sys.stderr)