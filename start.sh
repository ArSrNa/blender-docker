#!/bin/bash
cp config/flamenco-manager.yaml /usr/local/flamenco/flamenco-manager.yaml
cd /usr/local/flamenco/
./flamenco-worker &
./flamenco-manager &