#!/bin/bash

set -e

echo "====================================="
echo " Starting MySQL Backup Service"
echo "====================================="

echo "Timezone : $(date)"

echo "Cron Jobs"

crontab -l

echo "Starting Cron..."

crond -f -l 8