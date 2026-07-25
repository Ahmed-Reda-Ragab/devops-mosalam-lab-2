$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

python -m pip install --user locust
python -m locust -f .\locustfile_web.py --host=https://3.208.13.224 --web-port=8089
