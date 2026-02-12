# Architecture

## ファイル構成

```
tmux-toggl/
├── pomo.tmux                  # プラグインエントリポイント
├── scripts/
│   ├── helpers.sh             # tmuxオプション操作ヘルパー
│   └── toggl/
│       ├── main.sh            # コマンドハンドラ
│       ├── project-select.sh  # プロジェクト選択UI（tmux popup + fzf）
│       ├── session-init.sh    # セッション開始処理（API POST）
│       ├── session-overwrite.sh # セッション上書き処理（プロジェクト選択 + API PUT）
│       ├── env                # TOGGL_API_TOKEN（git管理外）
│       └── env.template       # envのテンプレート
├── README.md
└── ARCHITECTURE.md
```

## 状態管理

### セッションキャッシュ

`$HOME/.toggl_session` にキャッシュファイルを置く。`source` 可能な形式。

```
TOGGL_DESCRIPTION="作業内容"
TOGGL_PROJECT="プロジェクト名"
TOGGL_START_UNIXTIME=1739260800
TOGGL_STOPPED=0
TOGGL_STOPPED_TIME=
TOGGL_LAST_CHECK=1739260800
```

| 変数 | 説明 |
|------|------|
| `TOGGL_DESCRIPTION` | セッション名 |
| `TOGGL_PROJECT` | プロジェクト名（未指定なら空） |
| `TOGGL_START_UNIXTIME` | 開始時刻（Unix秒） |
| `TOGGL_STOPPED` | `0`=実行中, `1`=停止済み |
| `TOGGL_STOPPED_TIME` | 停止時刻 `HH:MM`（停止後のみ） |
| `TOGGL_LAST_CHECK` | 最終API同期時刻（Unix秒） |

停止後もキャッシュは保持する。次回 `start` で上書きされる。

### プロジェクトキャッシュ

`$HOME/.local/share/tmux-toggl-projects` に `id\tname` 形式で保存。

```
12345	ProjectA
67890	ProjectB
```

`Prefix + o`（明示的sync）で更新される。定期更新ではこのキャッシュから `project_id` → プロジェクト名を引く。

## API

Toggl Track API v9。Basic認証（`TOGGL_API_TOKEN:api_token`）。

| 操作 | エンドポイント |
|------|---------------|
| 現在のエントリー取得 | `GET /me/time_entries/current` |
| タイマー開始 | `POST /workspaces/{wid}/time_entries` |
| タイマー更新 | `PUT /workspaces/{wid}/time_entries/{id}` |
| タイマー停止 | `PATCH /workspaces/{wid}/time_entries/{id}/stop` |
| workspace_id取得 | `GET /me` → `.default_workspace_id` |
| プロジェクト一覧 | `GET /workspaces/{wid}/projects?active=true` |

APIが返す `start` フィールドはUTC。`date -j -u -f` でUnix秒に変換する。

### APIリクエスト数

| 操作 | リクエスト数 | 内訳 |
|------|:---:|------|
| `Prefix + p` (start) | 2 | GET /me, POST time_entries |
| `Prefix + P` (stop) | 2 | GET current, PATCH stop |
| `Prefix + o` (sync) | 3 | GET /me, GET projects, GET current |
| `Prefix + O` (overwrite) | 2 | GET current, PUT time_entries |
| 定期更新（60秒） | 1 | GET current |

※ プロジェクトキャッシュがない場合、初回はプロジェクト一覧取得で +2（GET /me, GET projects）。プロジェクトID解決のAPIフォールバックで +1。

## コマンド

`main.sh <command>` で実行。

| コマンド | 動作 |
|----------|------|
| `start` | tmux popup → `project-select.sh` → `session-init.sh` |
| `stop` | 確認プロンプト → `stop_ok` |
| `stop_ok` | API停止、キャッシュに `TOGGL_STOPPED=1` を記録 |
| `sync` | `sync_projects` + `sync_current`（キャッシュを強制更新） |
| `overwrite` | tmux popup → `session-overwrite.sh` |
| `time` | 実行中: 経過時間 `mm:ss` / 停止後: 停止時刻 `HH:MM` |
| `name` | `description @project` を出力 |
| `color` | 実行中: `brightred` / 停止後: `green` |

## API同期の頻度制御

`time`, `name`, `color` はtmuxステータスバーから毎秒呼ばれる。毎回APIを叩かないために `load_cache` で制御する。

1. キャッシュファイルが存在しない → `sync_current`（API呼び出し）
2. `TOGGL_STOPPED=1` → API再同期しない
3. `TOGGL_LAST_CHECK` から `CHECK_DURATION_TIME`（60秒）未経過 → キャッシュを読む
4. 60秒経過 → `sync_current`（API呼び出し、プロジェクト名はプロジェクトキャッシュから解決）
5. 外部から停止された場合（API が `null` を返す）→ キャッシュを `TOGGL_STOPPED=1` に更新

## tmux連携

### キーバインド

| キー | コマンド |
|------|---------|
| `Prefix + p` | `start` |
| `Prefix + P` | `stop` |
| `Prefix + o` | `sync`（プロジェクトキャッシュ + セッションキャッシュを強制更新） |
| `Prefix + O` | `overwrite`（実行中セッションのname/projectを変更） |

### ステータスバー補間

`pomo.tmux` が `status-left` / `status-right` 内の以下を置換する。

| 補間変数 | 呼び出し |
|----------|---------|
| `#{pomo_status}` | `main.sh time` |
| `#{pomo_name}` | `main.sh name` |
| `#{pomo_color}` | `main.sh color` |

### project-select.sh

`tmux display-popup -E -w 60% -h 40%` で起動。プロジェクトキャッシュから一覧を読み、fzf で選択後、description を入力させ、`exec session-init.sh` に渡す。「(なし)」を選択するとプロジェクト未指定で開始できる。

### session-init.sh

`project-select.sh` から `exec` で呼ばれる。API POST でTogglタイマーを開始し、キャッシュを書き込み、`status-interval` を1秒に設定する。

### session-overwrite.sh

`tmux display-popup -E -w 60% -h 40%` で起動。現在のセッション情報を表示しつつ、fzf でプロジェクト再選択、description を入力させ、API PUT で実行中エントリーを更新する。
