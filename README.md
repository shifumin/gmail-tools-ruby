# Gmail Tools Ruby

A collection of Ruby CLI tools for Gmail API. Search and fetch emails with OAuth 2.0 authentication (read-only).

## Features

- **Search emails** with Gmail query syntax
- **Fetch single email** by message ID
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
ruby gmail_authenticator.rb
```

A browser will open for Google authentication. Enter the authorization code when prompted.
Token is saved to `~/.credentials/gmail-readonly-token.yaml`.

## Usage

### Search Emails

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
```

### Fetch Single Email

```bash
# Fetch by message ID
ruby gmail_fetcher.rb --message-id='18abc123def456'

# Metadata only (faster)
ruby gmail_fetcher.rb --message-id='18abc123def456' --format=metadata
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
