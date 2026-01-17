# CLAUDE.md

## プロジェクト概要

Gmail APIを使ったRubyツール。OAuth 2.0認証でメールの検索・取得を行う（読み取り専用）。

## 開発コマンド

```bash
bundle install           # 依存関係インストール
bundle exec rubocop      # リンター実行
bundle exec rubocop -a   # リンター自動修正
```

## コーディング規約

- YARDコメントを使用（`@param`, `@return`, `@raise`）
- 出力はJSON形式で統一
- RuboCop設定は `.rubocop.yml` を参照

## 環境変数

| 変数名 | 説明 |
|--------|------|
| `GOOGLE_CLIENT_ID` | OAuth Client ID |
| `GOOGLE_CLIENT_SECRET` | OAuth Client Secret |

認証トークン保存先: `~/.credentials/gmail-readonly-token.yaml`

## 注意事項

- 認証トークンファイルはコミット禁止（機密情報）
- Gmail readonlyスコープのみ使用（送信・削除不可）
- テストファイルは未作成
