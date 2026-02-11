#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/env"

TOGGL_API_URL="https://api.track.toggl.com/api/v9"
AUTH="${TOGGL_API_TOKEN}:api_token"
PROJECTS_CACHE="$HOME/.local/share/tmux-toggl-projects"

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
SELECTED=$(printf "(なし)\n%s" "$PROJECTS" | fzf --preview="" --prompt="Project> " --header="プロジェクトを選択")

if [ -z "$SELECTED" ]; then
	exit 0
fi

# description 入力
printf "Description: "
read -r DESCRIPTION

if [ -z "$DESCRIPTION" ]; then
	exit 0
fi

# session-init.sh に渡す引数を組み立て
if [ "$SELECTED" = "(なし)" ]; then
	exec "$CURRENT_DIR/session-init.sh" "$DESCRIPTION"
else
	exec "$CURRENT_DIR/session-init.sh" "$DESCRIPTION @${SELECTED}"
fi
