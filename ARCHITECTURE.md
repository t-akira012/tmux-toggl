# Architecture

## ファイル構成

```
tmux-toggl/
├── pomo.tmux                  # プラグインエントリポイント
├── scripts/
│   ├── helpers.sh             # tmuxオプション操作ヘルパー
│   └── toggl/
│       ├── main.sh            # コマンドハンドラ
│       ├── session-init.sh    # セッション開始処理
│       ├── env                # TOGGL_API_TOKEN（git管理外）
│       └── env.template       # envのテンプレート
├── README.md
└── ARCHITECTURE.md
```

## 状態管理

`$HOME/.toggl_session` にキャッシュファイルを置く。`source` 可能な形式。

```
TOGGL_DESCRIPTION="作業内容"
TOGGL_START_UNIXTIME=1739260800
TOGGL_STOPPED=0
TOGGL_STOPPED_TIME=
TOGGL_LAST_CHECK=1739260800
```

| 変数 | 説明 |
|------|------|
| `TOGGL_DESCRIPTION` | セッション名 |
| `TOGGL_START_UNIXTIME` | 開始時刻（Unix秒） |
| `TOGGL_STOPPED` | `0`=実行中, `1`=停止済み |
| `TOGGL_STOPPED_TIME` | 停止時刻 `HH:MM`（停止後のみ） |
| `TOGGL_LAST_CHECK` | 最終API同期時刻（Unix秒） |

停止後もキャッシュは保持する。次回 `start` で上書きされる。

## API

Toggl Track API v9。Basic認証（`TOGGL_API_TOKEN:api_token`）。

| 操作 | エンドポイント |
|------|---------------|
| 現在のエントリー取得 | `GET /me/time_entries/current` |
| タイマー開始 | `POST /workspaces/{wid}/time_entries` |
| タイマー停止 | `PATCH /workspaces/{wid}/time_entries/{id}/stop` |
| workspace_id取得 | `GET /me` → `.default_workspace_id` |

APIが返す `start` フィールドはUTC。`date -j -u -f` でUnix秒に変換する。

## コマンド

`main.sh <command>` で実行。

| コマンド | API呼び出し | 動作 |
|----------|-------------|------|
| `start` | なし | tmuxプロンプト → `session-init.sh` |
| `stop` | なし | 確認プロンプト → `stop_ok` |
| `stop_ok` | PATCH | API停止、キャッシュに `TOGGL_STOPPED=1` を記録 |
| `sync` | GET current | 強制API同期 |
| `time` | 条件付き | 実行中: 経過時間 `mm:ss` / 停止後: 停止時刻 `HH:MM` |
| `name` | 条件付き | セッション名を出力 |
| `color` | 条件付き | 実行中: `brightred` / 停止後: `green` |

## API同期の頻度制御

`time`, `name`, `color` はtmuxステータスバーから毎秒呼ばれる。毎回APIを叩かないために `load_cache` で制御する。

1. キャッシュファイルが存在しない → `sync_current`（API呼び出し）
2. `TOGGL_STOPPED=1` → API再同期しない
3. `TOGGL_LAST_CHECK` から `CHECK_DURATION_TIME`（60秒）未経過 → キャッシュを読む
4. 60秒経過 → `sync_current`（API呼び出し）

## tmux連携

### キーバインド

| キー | コマンド |
|------|---------|
| `Prefix + p` | `start` |
| `Prefix + P` | `stop` |
| `Prefix + o` | `sync` |

### ステータスバー補間

`pomo.tmux` が `status-left` / `status-right` 内の以下を置換する。

| 補間変数 | 呼び出し |
|----------|---------|
| `#{pomo_status}` | `main.sh time` |
| `#{pomo_name}` | `main.sh name` |
| `#{pomo_color}` | `main.sh color` |

### session-init.sh

`tmux command-prompt` 経由で呼ばれる。API POST でTogglタイマーを開始し、キャッシュを書き込み、`status-interval` を1秒に設定する。
