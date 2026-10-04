#!/usr/bin/env bash
# Name: 0_start_db.sh
# Purpose: start the Oracle container in Docker and wait until the database is ready
# Usage: scripts/0_start_db.sh (container name defaults to oracle-db; override with ORACLE_CONTAINER)
# Requires: Docker Desktop running; the container already exists (see Setup in README)
# Called by: run manually before any table-creation or loading script
set -euo pipefail  # stop immediately if any step fails

container="${ORACLE_CONTAINER:-oracle-db}"  # container name
docker start "$container" >/dev/null  # start the container; fine if it is already running
for _ in $(seq 1 100); do  # wait at most 100 times
  status=$(docker inspect "$container" --format '{{.State.Health.Status}}')  # read health status
  if [ "$status" = "healthy" ]; then echo "Database is ready"; exit 0; fi  # done once healthy
  sleep 3  # not ready yet: wait another 3 seconds
done
echo "Database still not ready after 5 minutes; run docker logs $container to see why" >&2  # timeout message
exit 1  # exit with failure
