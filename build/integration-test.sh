#!/bin/bash
# End-to-end test of an Overleaf CE image:
# start it with MongoDB and Redis, create the first admin via the launchpad,
# log in, create a project, compile it and check that a PDF comes out.
# Also fails on crash-looping services or module resolution errors in the logs.
#
# Usage: build/integration-test.sh <image>
set -euo pipefail

IMAGE=${1:?usage: $0 <image>}
NET=ol-test
PORT=8080
BASE="http://localhost:$PORT"
EMAIL=admin@example.com
PASSWORD="ci-$(openssl rand -hex 12)"
JAR=$(mktemp)

log() { echo "::group::$*"; }
endlog() { echo "::endgroup::"; }

cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "::error::integration test failed, dumping logs"
    docker logs overleaf 2>&1 | tail -100 || true
    docker exec overleaf bash -c 'for f in /var/log/overleaf/*.log; do echo "===== $f"; tail -50 "$f"; done' || true
  fi
  docker rm -f overleaf mongo redis > /dev/null 2>&1 || true
  docker network rm "$NET" > /dev/null 2>&1 || true
  rm -f "$JAR"
  exit "$status"
}
trap cleanup EXIT

csrf() {
  # $1: page to read the CSRF token from (shares the session cookie jar)
  curl -fsS -b "$JAR" -c "$JAR" "$BASE$1" \
    | grep -oE 'name="ol-csrfToken" content="[^"]+"' | sed 's/.*content="//; s/"$//'
}

post_json() {
  # $1: path, $2: csrf token, $3: json body
  curl -fsS -b "$JAR" -c "$JAR" -X POST "$BASE$1" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -H "X-Csrf-Token: $2" -d "$3"
}

log "Start MongoDB, Redis and Overleaf"
docker network create "$NET" > /dev/null
docker run -d --name mongo --network "$NET" mongo:8.0 --replSet overleaf > /dev/null
docker run -d --name redis --network "$NET" redis:7.4 > /dev/null

for _ in $(seq 60); do
  docker exec mongo mongosh --quiet --eval 'db.runCommand({ping: 1}).ok' > /dev/null 2>&1 && break
  sleep 2
done
docker exec mongo mongosh --quiet --eval \
  'rs.initiate({_id: "overleaf", members: [{_id: 0, host: "mongo:27017"}]})'

docker run -d --name overleaf --network "$NET" -p "$PORT:80" \
  -e OVERLEAF_MONGO_URL=mongodb://mongo/sharelatex \
  -e OVERLEAF_REDIS_HOST=redis \
  -e REDIS_HOST=redis \
  -e OVERLEAF_SITE_URL="$BASE" \
  -e OVERLEAF_APP_NAME="CI Test" \
  -e EMAIL_CONFIRMATION_DISABLED=true \
  -e OVERLEAF_INVITE_TOKEN_SECRET="$(openssl rand -base64 32)" \
  "$IMAGE" > /dev/null
endlog

log "Wait for Overleaf to come up"
for i in $(seq 120); do
  if curl -fsS "$BASE/status" > /dev/null 2>&1; then
    echo "up after $((i * 3))s"
    break
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' overleaf)" != "true" ]; then
    echo "container exited"
    exit 1
  fi
  sleep 3
done
curl -fsS "$BASE/status"; echo
# MongoDB and Redis are exercised by the steps below (admin, login, project).
endlog

log "Create admin via launchpad and log in"
token=$(csrf /launchpad)
post_json /launchpad/register_admin "$token" \
  "$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email: $e, password: $p}')"
echo
token=$(csrf /login)
post_json /login "$token" \
  "$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email: $e, password: $p}')"
echo
endlog

log "Create a project and compile it"
token=$(csrf /project)
project_id=$(post_json /project/new "$token" '{"projectName": "ci-test"}' | jq -r .project_id)
echo "project_id=$project_id"
[ -n "$project_id" ] && [ "$project_id" != "null" ]

compile=$(post_json "/project/$project_id/compile" "$token" \
  '{"check": "silent", "draft": false, "incrementalCompilesEnabled": false}')
echo "$compile" | jq '{status, outputFiles: [.outputFiles[]?.path]}'
[ "$(echo "$compile" | jq -r .status)" = "success" ]

pdf_url=$(echo "$compile" | jq -r '.outputFiles[] | select(.path == "output.pdf") | .url')
[ -n "$pdf_url" ]
# Download completely first: piping into `head` makes curl fail with a write
# error (exit 23) under pipefail whenever head closes the pipe early.
pdf=$(mktemp)
curl -fsS -b "$JAR" -o "$pdf" "$BASE$pdf_url"
[ "$(head -c 5 "$pdf")" = "%PDF-" ]
echo "output.pdf OK ($(stat -c %s "$pdf") bytes)"
rm -f "$pdf"
endlog

log "Check services and logs"
# Every enabled runit service (no `down` file, e.g. phusion's sshd is disabled)
# must be up and must not have been restarted recently: give them 30s, then a
# crash-looping service shows up with a low uptime.
sleep 30
docker exec overleaf bash -c 'for s in /etc/service/*; do [ -e "$s/down" ] || sv status "$s"; done' | tee /dev/stderr \
  | awk '$1 != "run:" { bad = 1 } match($0, /\) [0-9]+s/) { if (substr($0, RSTART + 2, RLENGTH - 3) + 0 < 25) bad = 1 } END { exit bad }'

# Module resolution errors (e.g. a pruned yarn cache entry that was still needed)
if docker exec overleaf grep -rnE "MODULE_NOT_FOUND|ERR_MODULE_NOT_FOUND|Qualified path resolution failed|tried to access .* (but|which) it isn't declared|\.zip/node_modules.*ENOENT" /var/log/overleaf; then
  echo "module resolution errors found in logs"
  exit 1
fi
endlog

echo "integration test passed"
