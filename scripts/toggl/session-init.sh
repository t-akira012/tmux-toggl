#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -eq 0 ]; then
	tmux display-message "TOGGL: require session title."
	exit 0
fi

# TOGGL_API_TOKEN
source $CURRENT_DIR/env

TOGGL_API_URL="https://api.track.toggl.com/api/v9"
AUTH="${TOGGL_API_TOKEN}:api_token"
CACHE_FILE="$HOME/.toggl_session"

DESCRIPTION=$*
WORKSPACE_ID=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/me" | jq -r '.default_workspace_id')
START=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
START_UNIXTIME=$(date +%s)

curl -s -X POST "${TOGGL_API_URL}/workspaces/${WORKSPACE_ID}/time_entries" \
	-H "Content-Type: application/json" \
	-u "$AUTH" \
	-d "$(cat <<EOF
{
  "created_with": "tmux_toggl",
  "description": "${DESCRIPTION}",
  "workspace_id": ${WORKSPACE_ID},
  "duration": -1,
  "start": "${START}"
}
EOF
)" >/dev/null

cat <<EOF > "$CACHE_FILE"
TOGGL_DESCRIPTION="${DESCRIPTION}"
TOGGL_START_UNIXTIME=${START_UNIXTIME}
TOGGL_LAST_CHECK=$(date +%s)
EOF

tmux display-message "Toggl started: $DESCRIPTION"
tmux set -g status-interval 1
tmux refresh-client -S
