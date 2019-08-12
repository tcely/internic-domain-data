#!/usr/bin/env bash

set -e

cd '/Users/cely/gitwork/github/internic-domain-data-cron'

bash scripts/update.sh

git push origin domains:domains
