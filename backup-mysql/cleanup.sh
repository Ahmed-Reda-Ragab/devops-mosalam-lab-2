#!/bin/bash

BACKUP_ROOT=/backup/backups

ls -1dt $BACKUP_ROOT/* | tail -n +31 | while read OLD
do

echo "Deleting $OLD"

rm -rf "$OLD"

done