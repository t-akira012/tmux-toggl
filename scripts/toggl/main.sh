#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND=$1

# TOGGL_API_TOKEN
source $CURRENT_DIR/env

TOGGL_API_URL="https://api.track.toggl.com/api/v9"
AUTH="${TOGGL_API_TOKEN}:api_token"
CACHE_FILE="$HOME/.toggl_session"
CHECK_DURATION_TIME=60

# キャッシュ書き込み
write_cache() {
	local DESCRIPTION="$1"
	local START_UNIXTIME="$2"
	local STOPPED="${3:-0}"
	local STOPPED_TIME="${4:-}"
	cat <<EOF > "$CACHE_FILE"
TOGGL_DESCRIPTION="${DESCRIPTION}"
TOGGL_START_UNIXTIME=${START_UNIXTIME}
TOGGL_STOPPED=${STOPPED}
TOGGL_STOPPED_TIME=${STOPPED_TIME}
TOGGL_LAST_CHECK=$(date +%s)
EOF
}

# APIから現在のエントリーを取得してキャッシュ更新
sync_current() {
	local CURRENT=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/me/time_entries/current")
	if [ "$CURRENT" = "null" ] || [ -z "$CURRENT" ]; then
		return 1
	fi
	local DESCRIPTION=$(echo "$CURRENT" | jq -r '.description')
	local START_ISO=$(echo "$CURRENT" | jq -r '.start')
	local START_UNIXTIME=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${START_ISO%%+*}" +%s 2>/dev/null || date -u -d "$START_ISO" +%s)
	write_cache "$DESCRIPTION" "$START_UNIXTIME" "0"
}

# キャッシュ読み込み（CHECK_DURATION_TIME経過時のみAPI再同期）
load_cache() {
	if [ ! -f "$CACHE_FILE" ]; then
		sync_current || return 1
	else
		source "$CACHE_FILE"
		# 停止済みならAPI再同期しない
		if [ "$TOGGL_STOPPED" = "1" ]; then
			return 0
		fi
		local NOW=$(date +%s)
		if [ $((NOW - TOGGL_LAST_CHECK)) -ge $CHECK_DURATION_TIME ]; then
			sync_current || return 1
		fi
	fi
	source "$CACHE_FILE"
}

start_session() {
	tmux command-prompt -p "TOGGL:" "run-shell '$CURRENT_DIR/session-init.sh \"%%\"'"
}

stop_session_confirm() {
	tmux command-prompt -p "Stop toggl session? (Enter or CTRL-C):" "run-shell '$CURRENT_DIR/main.sh stop_ok'"
}

stop_session() {
	local CURRENT=$(curl -s -u "$AUTH" "${TOGGL_API_URL}/me/time_entries/current")
	if [ "$CURRENT" = "null" ] || [ -z "$CURRENT" ]; then
		tmux display-message "No running session."
		exit 0
	fi
	local TIME_ENTRY_ID=$(echo "$CURRENT" | jq -r '.id')
	local WORKSPACE_ID=$(echo "$CURRENT" | jq -r '.workspace_id')
	local DESCRIPTION=$(echo "$CURRENT" | jq -r '.description')

	curl -s -X PATCH \
		"${TOGGL_API_URL}/workspaces/${WORKSPACE_ID}/time_entries/${TIME_ENTRY_ID}/stop" \
		-H "Content-Type: application/json" \
		-u "$AUTH" >/dev/null

	# 停止時刻と停止フラグを記録（キャッシュは消さない）
	source "$CACHE_FILE"
	write_cache "$DESCRIPTION" "$TOGGL_START_UNIXTIME" "1" "$(date +%H:%M)"

	tmux display-message "Toggl stopped."
	tmux refresh-client -S
}

get_time() {
	load_cache || exit 0
	if [ "$TOGGL_STOPPED" = "1" ]; then
		# 停止後は停止時刻を表示
		echo "$TOGGL_STOPPED_TIME"
	else
		# 実行中は経過時間を表示
		local NOW=$(date +%s)
		local DIFF=$((NOW - TOGGL_START_UNIXTIME))
		local MM=$((DIFF / 60))
		local SS=$((DIFF % 60))
		printf "%02d:%02d" "$MM" "$SS"
	fi
}

get_name() {
	load_cache || exit 0
	echo "$TOGGL_DESCRIPTION"
}

get_color() {
	load_cache || exit 0
	if [ "$TOGGL_STOPPED" = "1" ]; then
		echo "green"
	else
		echo "brightred"
	fi
}

# コマンドディスパッチ
if [ "$COMMAND" = "start" ]; then
	start_session
elif [ "$COMMAND" = "stop" ]; then
	stop_session_confirm
elif [ "$COMMAND" = "stop_ok" ]; then
	stop_session
elif [ "$COMMAND" = "sync" ]; then
	sync_current
	tmux display-message "Toggl synced."
	tmux refresh-client -S
elif [ "$COMMAND" = "time" ]; then
	get_time
elif [ "$COMMAND" = "name" ]; then
	get_name
elif [ "$COMMAND" = "color" ]; then
	get_color
fi
