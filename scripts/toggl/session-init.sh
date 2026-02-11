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

INPUT="$*"
WORKSPACE_ID=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/me" | jq -r '.default_workspace_id')

# @プロジェクト名をパース
PROJECT_ID=""
PROJECT_NAME=""
if [[ "$INPUT" =~ @([^ ]+) ]]; then
	PROJECT_NAME="${BASH_REMATCH[1]}"
	# プロジェクト名からproject_idを取得
	PROJECT_ID=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/workspaces/${WORKSPACE_ID}/projects" \
		| jq -r --arg name "$PROJECT_NAME" '.[] | select(.name == $name) | .id')
	if [ -z "$PROJECT_ID" ]; then
		tmux display-message "TOGGL: project '${PROJECT_NAME}' not found."
		exit 0
	fi
fi

# @プロジェクト名を除いた部分をdescriptionにする
DESCRIPTION=$(echo "$INPUT" | sed "s/@${PROJECT_NAME}//;s/^ *//;s/ *$//")

START=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
START_UNIXTIME=$(date +%s)

# project_idがあればJSONに含める
if [ -n "$PROJECT_ID" ]; then
	PROJECT_JSON="\"project_id\": ${PROJECT_ID},"
else
	PROJECT_JSON=""
fi

curl -s -X POST "${TOGGL_API_URL}/workspaces/${WORKSPACE_ID}/time_entries" \
	-H "Content-Type: application/json" \
	-u "$AUTH" \
	-d "$(cat <<EOF
{
  "created_with": "tmux_toggl",
  "description": "${DESCRIPTION}",
  ${PROJECT_JSON}
  "workspace_id": ${WORKSPACE_ID},
  "duration": -1,
  "start": "${START}"
}
EOF
)" >/dev/null

cat <<EOF > "$CACHE_FILE"
TOGGL_DESCRIPTION="${DESCRIPTION}"
TOGGL_START_UNIXTIME=${START_UNIXTIME}
TOGGL_STOPPED=0
TOGGL_STOPPED_TIME=
TOGGL_LAST_CHECK=$(date +%s)
EOF

tmux display-message "Toggl started: ${PROJECT_NAME:+[$PROJECT_NAME] }$DESCRIPTION"
tmux set -g status-interval 1
tmux refresh-client -S
