# CLAUDE.md

このファイルはClaude Codeがこのリポジトリで作業する際のガイダンスを提供します。

## プロジェクト概要

Gmail APIを使ったRubyツール。OAuth 2.0認証でメールの検索・取得を行う（読み取り専用）。

### 主要ファイル

| ファイル | 説明 |
|---------|------|
| `gmail_searcher.rb` | メール検索（メイン機能） |
| `gmail_fetcher.rb` | 単一メール取得（ID指定） |
| `gmail_authenticator.rb` | OAuth認証 |

## 技術スタック

- Ruby >= 3.4.0
- google-apis-gmail_v1（Gmail API）
- googleauth（OAuth 2.0認証）
- rubocop（リンター）
- 環境変数管理: mise / direnv / shell export など任意

## コマンド

```bash
# 依存関係インストール
bundle install

# リンター実行
bundle exec rubocop

# リンター自動修正
bundle exec rubocop -a

# メール検索
ruby gmail_searcher.rb --query='from:apple.com AirTag'

# 日付範囲指定で検索
ruby gmail_searcher.rb --query='from:amazon.co.jp after:2025/01/01 before:2025/06/01'

# 結果件数制限
ruby gmail_searcher.rb --query='subject:invoice' --max-results=5

# 本文なし（高速）
ruby gmail_searcher.rb --query='is:unread' --no-body

# 単一メール取得
ruby gmail_fetcher.rb --message-id='18abc123def456'
```

## Gmail検索クエリ演算子

| 演算子 | 例 | 説明 |
|--------|-----|------|
| `from:` | `from:apple.com` | 送信元 |
| `to:` | `to:me@example.com` | 宛先 |
| `subject:` | `subject:invoice` | 件名 |
| `after:` | `after:2025/01/01` | 日付以降 |
| `before:` | `before:2025/06/01` | 日付以前 |
| `newer_than:` | `newer_than:7d` | 相対日付 |
| `has:attachment` | - | 添付ファイルあり |
| `label:` | `label:important` | ラベル |

## コーディング規約

### RuboCop設定（.rubocop.yml）

- 行長: 最大120文字
- 文字列リテラル: ダブルクォート統一
- frozen_string_literal: 必須
- メソッド長: 最大30行
- ABC複雑度: 最大30
- クラス長: 最大110行

### スタイルガイド

- クラス/モジュールのドキュメントコメントは任意
- YARDスタイルのコメントを使用（@param, @return, @raise）
- 出力はJSON形式で統一

## 環境変数

mise / direnv / shell export など任意の方法で設定:

| 変数名 | 説明 |
|--------|------|
| `GOOGLE_CLIENT_ID` | OAuth Client ID |
| `GOOGLE_CLIENT_SECRET` | OAuth Client Secret |

## 認証トークンの保存先

- `~/.credentials/gmail-readonly-token.yaml`

## 注意事項

- 認証トークンファイルはコミットしない
- Gmail readonly スコープのみ使用（送信・削除不可）
- テストファイルは現在存在しない
