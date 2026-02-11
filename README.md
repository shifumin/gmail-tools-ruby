# Gmail Tools Ruby

A collection of Ruby CLI tools for Gmail API with OAuth 2.0 authentication.

## Features

- **Search emails** with Gmail query syntax
- **Fetch single email** by message ID
- **Trash spam** - Move spam messages to trash in bulk
- **JSON output** for easy parsing
- **HTML body extraction** for HTML-only emails

## Requirements

- Ruby >= 3.4.0
- Google Cloud project with Gmail API enabled

## Installation

```bash
bundle install
```

## Setup

### 1. Configure Google Cloud Console

1. Create a project in [Google Cloud Console](https://console.cloud.google.com/)
2. Enable Gmail API
3. Create OAuth 2.0 Client ID (Desktop app)
4. Get Client ID and Client Secret

### 2. Set Environment Variables

```bash
export GOOGLE_CLIENT_ID="your-client-id"
export GOOGLE_CLIENT_SECRET="your-client-secret"
```

### 3. Authenticate

```bash
# Read-only (search, fetch)
ruby gmail_authenticator.rb

# Read and modify (required for trash spam)
ruby gmail_authenticator.rb --scope=modify
```

A browser will open for Google authentication. Enter the authorization code when prompted.

| Scope | Token file | Capabilities |
|-------|-----------|-------------|
| `readonly` (default) | `~/.credentials/gmail-readonly-token.yaml` | Search, fetch |
| `modify` | `~/.credentials/gmail-modify-token.yaml` | Search, fetch, trash |

## Usage

### Search Emails

#### Options

| Option | Required | Default | Description |
|--------|:--------:|---------|-------------|
| `--query=QUERY` | Yes | - | Gmail search query (same syntax as Gmail search box) |
| `--max-results=N` | No | 10 | Maximum number of results to return |
| `--no-body` | No | - | Exclude message body (faster response) |
| `--include-html` | No | - | Include HTML body content in response |
| `--include-spam-trash` | No | - | Include spam and trash messages in results |

**Note**: By default, HTML body is not included. The response only shows `has_html: true/false` flag. Use `--include-html` to get the actual HTML content.

#### Examples

```bash
# Basic search
ruby gmail_searcher.rb --query='from:example.com'

# Date range
ruby gmail_searcher.rb --query='after:2025/01/01 before:2025/06/01'

# Limit results
ruby gmail_searcher.rb --query='subject:invoice' --max-results=5

# Without body (faster)
ruby gmail_searcher.rb --query='is:unread' --no-body

# Include HTML body
ruby gmail_searcher.rb --query='from:amazon.com' --include-html

# List spam messages
ruby gmail_searcher.rb --query='label:spam' --include-spam-trash --no-body

# Search including spam and trash folders
ruby gmail_searcher.rb --query='from:example.com' --include-spam-trash
```

### Fetch Single Email

#### Options

| Option | Required | Default | Description |
|--------|:--------:|---------|-------------|
| `--message-id=ID` | Yes | - | Gmail message ID to fetch |
| `--format=FORMAT` | No | full | Response format (see below) |

**Format values**:

| Format | Description |
|--------|-------------|
| `full` | Complete message with body, HTML, and attachment info |
| `metadata` | Headers and metadata only (faster) |
| `minimal` | Minimal information (id, threadId, labelIds) |
| `raw` | Raw RFC 2822 formatted message |

#### Examples

```bash
# Fetch by message ID
ruby gmail_fetcher.rb --message-id='18abc123def456'

# Metadata only (faster)
ruby gmail_fetcher.rb --message-id='18abc123def456' --format=metadata
```

### Trash Spam

Move spam messages to trash in bulk. Requires `modify` scope authentication.

#### Options

| Option | Required | Default | Description |
|--------|:--------:|---------|-------------|
| `--max-results=N` | No | 500 | Maximum number of spam messages to process |
| `--dry-run` | No | - | Preview spam messages without trashing |
| `--batch-size=N` | No | 100 | Messages per batch API call (max: 100) |

#### Examples

```bash
# Preview spam (dry run)
ruby gmail_spam_trasher.rb --dry-run

# Trash up to 10 spam messages
ruby gmail_spam_trasher.rb --max-results=10

# Trash all spam (up to 500)
ruby gmail_spam_trasher.rb
```

### Gmail Query Operators

| Operator | Example | Description |
|----------|---------|-------------|
| `from:` | `from:example.com` | From sender |
| `to:` | `to:me@example.com` | To recipient |
| `subject:` | `subject:invoice` | Subject contains |
| `after:` | `after:2025/01/01` | After date |
| `before:` | `before:2025/06/01` | Before date |
| `newer_than:` | `newer_than:7d` | Within last N days |
| `has:attachment` | - | Has attachments |
| `label:` | `label:important` | Has label |
| `is:` | `is:unread` | Status |

## Output Format

```json
{
  "query": "from:example.com",
  "result_count": 1,
  "messages": [
    {
      "id": "18abc123def456",
      "thread_id": "18abc123def456",
      "date": "Wed, 15 Jan 2025 10:30:00 +0900",
      "from": "Example <noreply@example.com>",
      "to": "user@example.com",
      "subject": "Your order has shipped",
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

## License

MIT
