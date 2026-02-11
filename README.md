# tmux-toggl

Toggl Track と連携する tmux 時間管理プラグイン。

## Setup

```bash
cp scripts/toggl/env.template scripts/toggl/env
# env に TOGGL_API_TOKEN を設定
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Prefix + p` | タイマー開始（セッション名を入力） |
| `Prefix + P` | タイマー停止 |
| `Prefix + o` | API同期 |

## Status Bar

`#{pomo_status}` `#{pomo_name}` `#{pomo_color}` を tmux status-left/right で使用可能。

## Requirements

- curl
- jq
