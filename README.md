# Gmail Tools Ruby

Gmail API を使ったRubyツール集。OAuth 2.0認証でメールの検索・取得を行う。

## 主要ファイル

| ファイル | 説明 |
|---------|------|
| `gmail_authenticator.rb` | OAuth認証（読み取り専用） |
| `gmail_searcher.rb` | メール検索 |
| `gmail_fetcher.rb` | 単一メール取得（ID指定） |

## セットアップ

### 1. 依存関係インストール

```bash
bundle install
```

### 2. Google Cloud Console で OAuth 設定

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成
2. Gmail API を有効化
3. OAuth 2.0 クライアント ID を作成（デスクトップアプリ）
4. クライアントID・シークレットを取得

### 3. 環境変数設定

mise / direnv / shell export など任意の方法で設定:

```bash
export GOOGLE_CLIENT_ID="your-client-id"
export GOOGLE_CLIENT_SECRET="your-client-secret"
```

### 4. 認証

```bash
ruby gmail_authenticator.rb
```

ブラウザが開くので Google アカウントで認証し、表示されたコードを入力する。
トークンは `~/.credentials/gmail-readonly-token.yaml` に保存される。

## 使い方

### メール検索

```bash
# 基本検索
ruby gmail_searcher.rb --query='from:apple.com AirTag'

# 日付範囲指定
ruby gmail_searcher.rb --query='from:amazon.co.jp after:2025/01/01 before:2025/06/01'

# 結果件数制限
ruby gmail_searcher.rb --query='subject:invoice' --max-results=5

# 本文なし（高速）
ruby gmail_searcher.rb --query='is:unread' --no-body
```

### 単一メール取得

```bash
# メッセージIDを指定して取得
ruby gmail_fetcher.rb --message-id='18abc123def456'

# メタデータのみ（高速）
ruby gmail_fetcher.rb --message-id='18abc123def456' --format=metadata
```

## Gmail検索クエリ演算子

| 演算子 | 例 | 説明 |
|--------|-----|------|
| `from:` | `from:apple.com` | 送信元 |
| `to:` | `to:me@example.com` | 宛先 |
| `subject:` | `subject:invoice` | 件名 |
| `after:` | `after:2025/01/01` | 日付以降 |
| `before:` | `before:2025/06/01` | 日付以前 |
| `newer_than:` | `newer_than:7d` | 相対日付（7日以内） |
| `older_than:` | `older_than:1y` | 相対日付（1年以上前） |
| `has:attachment` | - | 添付ファイルあり |
| `filename:` | `filename:pdf` | 添付ファイル種類 |
| `label:` | `label:important` | ラベル |
| `is:` | `is:unread` | ステータス |

複数の演算子を組み合わせ可能:
```bash
ruby gmail_searcher.rb --query='from:apple.com subject:order after:2025/01/01'
```

## JSON出力形式

### 検索結果

```json
{
  "query": "from:apple.com AirTag",
  "result_count": 1,
  "messages": [
    {
      "id": "18abc123def456",
      "thread_id": "18abc123def456",
      "date": "Wed, 15 Jan 2025 10:30:00 +0900",
      "from": "Apple <noreply@email.apple.com>",
      "to": "user@example.com",
      "subject": "Your AirTag order has shipped",
      "snippet": "Your order is on its way...",
      "labels": ["INBOX", "CATEGORY_UPDATES"],
      "body": {
        "plain_text": "...",
        "has_html": true
      }
    }
  ]
}
```

## 技術スタック

- Ruby >= 3.4.0
- google-apis-gmail_v1（Gmail API）
- googleauth（OAuth 2.0認証）
- rubocop（リンター）

## 開発

```bash
# リンター実行
bundle exec rubocop

# 自動修正
bundle exec rubocop -a
```

## 注意事項

- 認証トークンファイルはコミットしない
- Gmail readonly スコープのみ使用（メールの読み取りのみ、送信・削除不可）
