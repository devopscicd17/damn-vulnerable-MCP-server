cat > ~/reinstall-dvmcp.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP="damn-vulnerable-mcp-server"
NAMESPACE="$(oc project -q)"
REPO="https://github.com/devopscicd17/damn-vulnerable-MCP-server.git"
WORKDIR="$HOME/damn-vulnerable-MCP-server"

echo "=================================================="
echo " DVMCP CLEAN INSTALL"
echo "=================================================="
echo "Namespace : $NAMESPACE"
echo "Application: $APP"
echo "Repository : $REPO"
echo

echo ">>> Checking OpenShift login..."
oc whoami
echo

echo ">>> Checking current project..."
oc project "$NAMESPACE"
echo

# --------------------------------------------------
# 1. DELETE PREVIOUS APPLICATION RESOURCES
# --------------------------------------------------

echo "=================================================="
echo "1. Removing previous DVMCP resources"
echo "=================================================="

oc delete route \
    -l app="$APP" \
    --ignore-not-found=true \
    2>/dev/null || true

oc delete route \
    "$APP" \
    "$APP-9002" "$APP-9003" "$APP-9004" "$APP-9005" \
    "$APP-9006" "$APP-9007" "$APP-9008" "$APP-9009" "$APP-9010" \
    --ignore-not-found=true \
    2>/dev/null || true

oc delete svc "$APP" --ignore-not-found=true

oc delete deployment "$APP" --ignore-not-found=true

oc delete buildconfig "$APP" --ignore-not-found=true

oc delete builds \
    -l buildconfig="$APP" \
    --ignore-not-found=true \
    2>/dev/null || true

oc delete imagestream "$APP" --ignore-not-found=true

echo
echo ">>> Waiting for old resources to disappear..."

sleep 5

# --------------------------------------------------
# 2. REMOVE OLD SOURCE DIRECTORY
# --------------------------------------------------

echo "=================================================="
echo "2. Removing old source tree"
echo "=================================================="

rm -rf "$WORKDIR"

# --------------------------------------------------
# 3. CLONE FRESH REPOSITORY
# --------------------------------------------------

echo "=================================================="
echo "3. Cloning fresh repository"
echo "=================================================="

cd "$HOME"

git clone "$REPO" "$WORKDIR"

cd "$WORKDIR"

echo
echo ">>> Git commit:"
git log -1 --oneline

# --------------------------------------------------
# 4. PIN MCP SDK TO VERSION 1
# --------------------------------------------------

echo
echo "=================================================="
echo "4. Pinning MCP SDK to v1"
echo "=================================================="

if [ -f requirements.txt ]; then
    if grep -q '^mcp\[cli\]' requirements.txt; then
        sed -i 's/^mcp\[cli\].*/mcp[cli]<2/' requirements.txt
    else
        echo "mcp[cli]<2" >> requirements.txt
    fi
fi

if [ -f pyproject.toml ]; then
    sed -i 's/version = ">=0\.5\.0"/version = "<2"/' pyproject.toml
fi

echo
echo ">>> MCP dependency:"
grep -n "mcp" requirements.txt 2>/dev/null || true
grep -n "mcp" pyproject.toml 2>/dev/null || true

# --------------------------------------------------
# 5. OPENSHIFT SUPERVISOR COMPATIBILITY
# --------------------------------------------------

echo
echo "=================================================="
echo "5. Checking OpenShift Supervisor configuration"
echo "=================================================="

if [ -f supervisord.conf ]; then

    # Remove root user directive
    sed -i '/^[[:space:]]*user[[:space:]]*=[[:space:]]*root[[:space:]]*$/d' supervisord.conf

    # Use writable /tmp locations
    sed -i 's#^logfile=.*#logfile=/tmp/supervisord.log#' supervisord.conf
    sed -i 's#^pidfile=.*#pidfile=/tmp/supervisord.pid#' supervisord.conf

    # Challenge stdout/stderr
    sed -i 's#/var/log/supervisor#/tmp/supervisor#g' supervisord.conf

    echo ">>> Updated supervisord.conf"
    grep -nE '^\[supervisord\]|nodaemon|user|logfile|pidfile|stdout_logfile|stderr_logfile' supervisord.conf || true

else
    echo "WARNING: supervisord.conf not found."
fi

# --------------------------------------------------
# 6. MAKE SUPERVISOR DIRECTORY OPENSHIFT COMPATIBLE
# --------------------------------------------------

echo
echo "=================================================="
echo "6. Preparing Dockerfile for OpenShift"
echo "=================================================="

if [ -f Dockerfile ]; then

    if ! grep -q '/tmp/supervisor' Dockerfile; then
        cat >> Dockerfile <<'DOCKERFILE'

# OpenShift arbitrary UID compatibility
RUN mkdir -p /tmp/supervisor && \
    chgrp -R 0 /tmp/supervisor && \
    chmod -R g=u /tmp/supervisor
DOCKERFILE
    fi

else
    echo "ERROR: Dockerfile not found."
    exit 1
fi

# --------------------------------------------------
# 7. SHOW FINAL CHANGES
# --------------------------------------------------

echo
echo "=================================================="
echo "7. Final source configuration"
echo "=================================================="

echo
echo "--- requirements.txt ---"
cat requirements.txt

echo
echo "--- MCP dependency in pyproject.toml ---"
grep -n "mcp" pyproject.toml 2>/dev/null || true

echo
echo "--- Git status ---"
git status --short

# --------------------------------------------------
# 8. CREATE OPENSHIFT BUILD
# --------------------------------------------------

echo
echo "=================================================="
echo "8. Creating OpenShift BuildConfig"
echo "=================================================="

oc new-build \
    --binary \
    --name="$APP" \
    --strategy=docker

# --------------------------------------------------
# 9. BUILD IMAGE
# --------------------------------------------------

echo
echo "=================================================="
echo "9. Building DVMCP image"
echo "=================================================="

oc start-build "$APP" \
    --from-dir="$WORKDIR" \
    --follow

# --------------------------------------------------
# 10. DEPLOY
# --------------------------------------------------

echo
echo "=================================================="
echo "10. Deploying DVMCP"
echo "=================================================="

oc create deployment "$APP" \
    --image="image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/${APP}:latest"

# --------------------------------------------------
# 11. WAIT FOR DEPLOYMENT
# --------------------------------------------------

echo
echo "=================================================="
echo "11. Waiting for pod"
echo "=================================================="

oc rollout status deployment/"$APP" --timeout=300s

sleep 5

oc get pods -l app="$APP" -o wide

# --------------------------------------------------
# 12. CREATE SERVICE WITH ALL 10 PORTS
# --------------------------------------------------

echo
echo "=================================================="
echo "12. Creating Service"
echo "=================================================="

oc expose deployment "$APP" \
    --port=9001 \
    --target-port=9001 \
    --name="$APP"

for p in 9002 9003 9004 9005 9006 9007 9008 9009 9010; do

    oc patch svc "$APP" --type=json -p="[
      {
        \"op\":\"add\",
        \"path\":\"/spec/ports/-\",
        \"value\":{
          \"name\":\"${p}-tcp\",
          \"port\":${p},
          \"protocol\":\"TCP\",
          \"targetPort\":${p}
        }
      }
    ]"

done

echo
oc get svc "$APP"

# --------------------------------------------------
# 13. CREATE ROUTE FOR PORT 9001
# --------------------------------------------------

echo
echo "=================================================="
echo "13. Creating Route for Challenge 1"
echo "=================================================="

oc create route edge "$APP" \
    --service="$APP" \
    --port=9001-tcp \
    2>/dev/null || true

# --------------------------------------------------
# 14. CREATE ROUTES 9002-9010
# --------------------------------------------------

echo
echo "=================================================="
echo "14. Creating Routes for Challenges 2-10"
echo "=================================================="

for p in 9002 9003 9004 9005 9006 9007 9008 9009 9010; do

    oc create route edge "$APP-$p" \
        --service="$APP" \
        --port="${p}-tcp"

done

# --------------------------------------------------
# 15. WAIT FOR APPLICATION
# --------------------------------------------------

echo
echo "=================================================="
echo "15. Waiting for application"
echo "=================================================="

sleep 10

POD="$(oc get pods -l app="$APP" \
    -o jsonpath='{.items[0].metadata.name}')"

echo
echo "POD=$POD"

# --------------------------------------------------
# 16. MCP VERSION
# --------------------------------------------------

echo
echo "=================================================="
echo "16. Checking MCP SDK"
echo "=================================================="

oc exec "$POD" -- python -m pip show mcp | grep -E '^(Name|Version):'

# --------------------------------------------------
# 17. FASTMCP TEST
# --------------------------------------------------

echo
echo "=================================================="
echo "17. Testing FastMCP"
echo "=================================================="

oc exec "$POD" -- python -c \
"from mcp.server.fastmcp import FastMCP, Context; print('FastMCP import OK')"

# --------------------------------------------------
# 18. CHECK PORTS
# --------------------------------------------------

echo
echo "=================================================="
echo "18. Checking ports 9001-9010"
echo "=================================================="

oc exec "$POD" -- sh -c '
for p in 9001 9002 9003 9004 9005 9006 9007 9008 9009 9010; do
    hex=$(printf "%04X" "$p")

    if grep -qi ":$hex " /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
        echo "PORT $p LISTENING"
    else
        echo "PORT $p NOT LISTENING"
    fi
done
'

# --------------------------------------------------
# 19. CHECK POD STATUS
# --------------------------------------------------

echo
echo "=================================================="
echo "19. Pod status"
echo "=================================================="

oc get pods -l app="$APP"

# --------------------------------------------------
# 20. CHECK ROUTES
# --------------------------------------------------

echo
echo "=================================================="
echo "20. DVMCP ROUTES"
echo "=================================================="

oc get route \
    -o custom-columns='NAME:.metadata.name,HOST:.spec.host,PORT:.spec.port.targetPort'

# --------------------------------------------------
# 21. FINAL LOGS
# --------------------------------------------------

echo
echo "=================================================="
echo "21. Application logs"
echo "=================================================="

oc logs "$POD" --tail=100

echo
echo "=================================================="
echo " DVMCP INSTALL COMPLETE"
echo "=================================================="

echo
echo "Namespace:"
echo "$NAMESPACE"

echo
echo "Pod:"
echo "$POD"

echo
echo "Routes:"
oc get route

echo
echo "Service:"
oc get svc "$APP"

echo
echo "=================================================="
echo "Use the HTTPS Route URLs above with your MCP client."
echo "=================================================="
EOF

chmod +x ~/reinstall-dvmcp.sh
