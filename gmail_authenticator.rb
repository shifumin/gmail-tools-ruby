#!/usr/bin/env ruby
# frozen_string_literal: true

require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"
require "fileutils"
require "optparse"

# GmailAuthenticator handles the OAuth 2.0 authentication flow for Gmail API
class GmailAuthenticator
  OOB_URI = "urn:ietf:wg:oauth:2.0:oob"
  CREDENTIALS_DIR = File.join(Dir.home, ".credentials")
  APPLICATION_NAME = "Gmail Tools"

  SCOPE_CONFIG = {
    "readonly" => {
      scope: Google::Apis::GmailV1::AUTH_GMAIL_READONLY,
      token_path: File.join(CREDENTIALS_DIR, "gmail-readonly-token.yaml"),
      description: "read-only"
    },
    "modify" => {
      scope: Google::Apis::GmailV1::AUTH_GMAIL_MODIFY,
      token_path: File.join(CREDENTIALS_DIR, "gmail-modify-token.yaml"),
      description: "read and modify"
    }
  }.freeze

  DEFAULT_SCOPE = "readonly"
  VALID_SCOPES = SCOPE_CONFIG.keys.freeze

  # Gmail認証器を初期化する
  #
  # @param scope [String] OAuthスコープ名 ("readonly" or "modify")
  # @raise [ArgumentError] 無効なスコープが指定された場合
  # @raise [RuntimeError] 必要な環境変数が設定されていない場合
  def initialize(scope: DEFAULT_SCOPE)
    validate_scope(scope)
    @scope_config = SCOPE_CONFIG[scope]
    validate_environment
    ensure_credentials_directory
  end

  # Gmail API用のOAuth 2.0認証を実行する
  #
  # 既に認証情報が存在する場合は、認証済みであることを示すメッセージを表示する
  # そうでない場合は、ブラウザを開いて認証コードの入力を促すOAuthフローを開始する
  #
  # @return [void]
  def authenticate
    client_id = Google::Auth::ClientId.new(
      ENV.fetch("GOOGLE_CLIENT_ID", nil),
      ENV.fetch("GOOGLE_CLIENT_SECRET", nil)
    )

    token_store = Google::Auth::Stores::FileTokenStore.new(file: @scope_config[:token_path])
    authorizer = Google::Auth::UserAuthorizer.new(client_id, @scope_config[:scope], token_store)
    user_id = "default"

    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      perform_authentication(authorizer, user_id)
    else
      show_already_authenticated_message
    end
  end

  private

  # 対話型のOAuth認証フローを実行する
  #
  # 認証URLを含むブラウザウィンドウを開き、ユーザーに認証コードの入力を促し、
  # 将来の使用のために認証情報を保存する
  #
  # @param authorizer [Google::Auth::UserAuthorizer] OAuthオーソライザインスタンス
  # @param user_id [String] 認証情報保存用のユーザー識別子
  # @return [void]
  def perform_authentication(authorizer, user_id)
    puts "=== Gmail OAuth 2.0 Setup (#{@scope_config[:description]}) ===\n",
         "Opening authorization URL in your browser...\n",
         "If the browser doesn't open automatically, please copy and paste this URL:"

    url = authorizer.get_authorization_url(base_url: OOB_URI)
    puts url, "\n"

    open_browser(url)

    puts "After authorizing, enter the authorization code:"
    code = gets.chomp

    authorizer.get_and_store_credentials_from_code(
      user_id: user_id,
      code: code,
      base_url: OOB_URI
    )

    puts "\n",
         "✓ Authentication successful!\n",
         "✓ Token saved to: #{@scope_config[:token_path]}\n",
         "You can now use Gmail tools with #{@scope_config[:description]} access."
  end

  def show_already_authenticated_message
    puts "✓ Already authenticated (#{@scope_config[:description]})!\n",
         "Token file: #{@scope_config[:token_path]}\n",
         "If you want to re-authenticate, delete the token file and run this script again."
  end

  # スコープが有効であることを検証する
  #
  # @param scope [String] スコープ名
  # @raise [ArgumentError] 無効なスコープの場合
  # @return [void]
  def validate_scope(scope)
    return if VALID_SCOPES.include?(scope)

    raise ArgumentError, "Invalid scope: '#{scope}'. Valid scopes: #{VALID_SCOPES.join(', ')}"
  end

  # デフォルトブラウザで認証URLを開く
  #
  # OSを検出して適切なコマンドを使用してブラウザを開く
  # macOS (darwin)、Linux、Windowsプラットフォームをサポート
  #
  # @param url [String] 開く認証URL
  # @return [void]
  def open_browser(url)
    case RUBY_PLATFORM
    when /darwin/
      system("open '#{url}'")
    when /linux/
      system("xdg-open '#{url}'")
    when /mingw|mswin/
      system("start '#{url}'")
    end
  end

  # 必要な環境変数が設定されていることを検証する
  #
  # @raise [RuntimeError] GOOGLE_CLIENT_IDまたはGOOGLE_CLIENT_SECRETが設定されていない場合
  # @return [void]
  def validate_environment
    raise "GOOGLE_CLIENT_ID is not set" unless ENV["GOOGLE_CLIENT_ID"]
    raise "GOOGLE_CLIENT_SECRET is not set" unless ENV["GOOGLE_CLIENT_SECRET"]
  end

  def ensure_credentials_directory
    FileUtils.mkdir_p(CREDENTIALS_DIR) unless File.directory?(CREDENTIALS_DIR)
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  options = { scope: GmailAuthenticator::DEFAULT_SCOPE }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby gmail_authenticator.rb [options]"

    opts.on("--scope=SCOPE", "OAuth scope: readonly (default), modify") do |v|
      options[:scope] = v
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  begin
    authenticator = GmailAuthenticator.new(scope: options[:scope])
    authenticator.authenticate
  rescue StandardError => e
    puts "Error: #{e.message}"
    exit 1
  end
end
