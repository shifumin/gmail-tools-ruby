# CLAUDE.md

## Project Overview

Ruby CLI tools for Gmail API. Performs email search, fetch, spam trash, and batch label modification via OAuth 2.0 authentication.

## Project Structure

| File | Description | Scope |
|------|-------------|-------|
| `gmail_authenticator.rb` | OAuth 2.0 authentication setup | readonly / modify |
| `gmail_searcher.rb` | Search messages with Gmail query syntax | readonly |
| `gmail_fetcher.rb` | Fetch a single message by ID | readonly |
| `gmail_spam_trasher.rb` | Bulk move spam messages to trash | modify |
| `gmail_batch_modifier.rb` | Batch add/remove labels on messages | modify |

## Development Commands

```bash
bundle install           # Install dependencies
bundle exec rubocop      # Run linter
bundle exec rubocop -a   # Run linter with auto-fix
```

## Coding Conventions

- YARD comments (`@param`, `@return`, `@raise`) on public methods
- JSON output for all tools
- See `.rubocop.yml` for linter settings

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GOOGLE_CLIENT_ID` | OAuth Client ID |
| `GOOGLE_CLIENT_SECRET` | OAuth Client Secret |

Token file locations:
- `~/.credentials/gmail-readonly-token.yaml` (readonly scope)
- `~/.credentials/gmail-modify-token.yaml` (modify scope)

## Notes

- Never commit token files (sensitive credentials)
- readonly scope: search and fetch only (no send, no delete)
- modify scope: search, fetch, trash, and batch label modify (no send, no permanent delete)
- No test files yet
