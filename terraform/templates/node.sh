#!/bin/bash
set -euo pipefail

# The instance profile takes a moment to propagate after launch. If the SSM agent starts before the
# credentials are there it backs off for 30 minutes, so wait for them and restart it.
until token=$(curl -fsS --max-time 5 -X PUT http://169.254.169.254/latest/api/token \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60") \
  && curl -fsS --max-time 5 -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/ | grep -q .; do
  sleep 5
done
systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service
