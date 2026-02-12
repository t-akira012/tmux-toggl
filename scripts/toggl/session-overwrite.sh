#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/env"

TOGGL_API_URL="https://api.track.toggl.com/api/v9"
AUTH="${TOGGL_API_TOKEN}:api_token"
CACHE_FILE="$HOME/.toggl_session"
PROJECTS_CACHE="$HOME/.local/share/tmux-toggl-projects"

# 現在のキャッシュを読み込み
if [ ! -f "$CACHE_FILE" ]; then
	echo "No active session."
	exit 0
fi
source "$CACHE_FILE"

# キャッシュがあればそれを使い、なければAPIから取得
if [ -f "$PROJECTS_CACHE" ]; then
	PROJECTS=$(cat "$PROJECTS_CACHE")
else
	WORKSPACE_ID=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/me" | jq -r '.default_workspace_id')
	PROJECTS=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/workspaces/${WORKSPACE_ID}/projects?active=true" \
		| jq -r '.[].name' | sort)
	mkdir -p "$(dirname "$PROJECTS_CACHE")"
	echo "$PROJECTS" > "$PROJECTS_CACHE"
fi

# fzf でプロジェクト選択（「(なし)」を先頭に追加）
SELECTED=$(printf "(なし)\n%s" "$PROJECTS" | fzf --preview="" --prompt="Project> " --header="現在: ${TOGGL_PROJECT:-(なし)}")

if [ -z "$SELECTED" ]; then
	exit 0
fi

# description 入力（空Enterで現在値を維持）
printf "Description [%s]: " "$TOGGL_DESCRIPTION"
read -r DESCRIPTION

if [ -z "$DESCRIPTION" ]; then
	DESCRIPTION="$TOGGL_DESCRIPTION"
fi

# プロジェクト解決
PROJECT_ID=""
PROJECT_NAME=""
if [ "$SELECTED" != "(なし)" ]; then
	PROJECT_NAME="$SELECTED"
fi

WORKSPACE_ID=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/me" | jq -r '.default_workspace_id')

if [ -n "$PROJECT_NAME" ]; then
	PROJECT_ID=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/workspaces/${WORKSPACE_ID}/projects" \
		| jq -r --arg name "$PROJECT_NAME" '.[] | select(.name == $name) | .id')
	if [ -z "$PROJECT_ID" ]; then
		tmux display-message "TOGGL: project '${PROJECT_NAME}' not found."
		exit 0
	fi
fi

# 現在のエントリーを取得
CURRENT=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/me/time_entries/current")
if [ "$CURRENT" = "null" ] || [ -z "$CURRENT" ]; then
	tmux display-message "TOGGL: no running entry."
	exit 0
fi

TIME_ENTRY_ID=$(echo "$CURRENT" | jq -r '.id')
START=$(echo "$CURRENT" | jq -r '.start')

# project_idがあればJSONに含める
if [ -n "$PROJECT_ID" ]; then
	PROJECT_JSON="\"project_id\": ${PROJECT_ID},"
else
	PROJECT_JSON=""
fi

curl -s -X PUT \
	"${TOGGL_API_URL}/workspaces/${WORKSPACE_ID}/time_entries/${TIME_ENTRY_ID}" \
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
TOGGL_PROJECT="${PROJECT_NAME}"
TOGGL_START_UNIXTIME=${TOGGL_START_UNIXTIME}
TOGGL_STOPPED=0
TOGGL_STOPPED_TIME=
TOGGL_LAST_CHECK=$(date +%s)
EOF

tmux display-message "Toggl updated: ${PROJECT_NAME:+[$PROJECT_NAME] }$DESCRIPTION"
tmux refresh-client -S
