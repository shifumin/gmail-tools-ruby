#!/usr/bin/env ruby
# frozen_string_literal: true

require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"
require "json"
require "optparse"
require "base64"

# GmailSearcher searches Gmail messages using Gmail API
class GmailSearcher
  APPLICATION_NAME = "Gmail Searcher"
  CREDENTIALS_DIR = File.join(Dir.home, ".credentials")
  TOKEN_PATH = File.join(CREDENTIALS_DIR, "gmail-readonly-token.yaml")
  SCOPE = Google::Apis::GmailV1::AUTH_GMAIL_READONLY
  DEFAULT_MAX_RESULTS = 10
  MAX_RESULTS_LIMIT = 100

  # GmailSearcherを初期化する
  #
  # @raise [RuntimeError] 認証情報が存在しない場合
  def initialize
    validate_credentials
    @service = Google::Apis::GmailV1::GmailService.new
    @service.client_options.application_name = APPLICATION_NAME
    @service.authorization = authorize
  end

  # Gmailを検索してJSON形式で結果を出力する
  #
  # @param query [String] Gmail検索クエリ
  # @param max_results [Integer] 最大取得件数
  # @param include_body [Boolean] メール本文を含めるか
  # @param include_html [Boolean] HTML本文を含めるか
  # @return [void]
  def search(query:, max_results: DEFAULT_MAX_RESULTS, include_body: true, include_html: false)
    message_ids = fetch_message_ids(query, max_results)
    messages = message_ids.map { |msg| fetch_message_detail(msg.id, include_body, include_html) }

    result = {
      query: query,
      result_count: messages.size,
      messages: messages
    }

    puts JSON.pretty_generate(result)
  end

  private

  # OAuth認証情報を取得する
  #
  # @return [Google::Auth::UserRefreshCredentials] 認証情報
  def authorize
    client_id = Google::Auth::ClientId.new(
      ENV.fetch("GOOGLE_CLIENT_ID", nil),
      ENV.fetch("GOOGLE_CLIENT_SECRET", nil)
    )

    token_store = Google::Auth::Stores::FileTokenStore.new(file: TOKEN_PATH)
    authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)

    authorizer.get_credentials("default")
  end

  # 認証情報が存在することを検証する
  #
  # @raise [RuntimeError] トークンファイルが存在しない場合
  # @return [void]
  def validate_credentials
    return if File.exist?(TOKEN_PATH)

    raise "No credentials found. Please run 'ruby gmail_authenticator.rb' first to authenticate."
  end

  # メッセージIDリストを取得する
  #
  # @param query [String] Gmail検索クエリ
  # @param max_results [Integer] 最大取得件数
  # @return [Array<Google::Apis::GmailV1::Message>] メッセージリスト
  def fetch_message_ids(query, max_results)
    messages = []
    page_token = nil

    loop do
      remaining = max_results - messages.size
      batch_size = [remaining, MAX_RESULTS_LIMIT].min

      response = @service.list_user_messages(
        "me",
        q: query,
        max_results: batch_size,
        page_token: page_token
      )

      break if response.messages.nil? || response.messages.empty?

      messages.concat(response.messages)
      break if messages.size >= max_results
      break if response.next_page_token.nil?

      page_token = response.next_page_token
    end

    messages.take(max_results)
  end

  # メッセージ詳細を取得する
  #
  # @param message_id [String] メッセージID
  # @param include_body [Boolean] 本文を含めるか
  # @param include_html [Boolean] HTML本文を含めるか
  # @return [Hash] メッセージデータ
  def fetch_message_detail(message_id, include_body, include_html)
    message = @service.get_user_message("me", message_id, format: "full")
    build_message_data(message, include_body, include_html)
  rescue StandardError => e
    { id: message_id, error: e.message }
  end

  # メッセージデータをハッシュに整形する
  #
  # @param message [Google::Apis::GmailV1::Message] メッセージ
  # @param include_body [Boolean] 本文を含めるか
  # @param include_html [Boolean] HTML本文を含めるか
  # @return [Hash] 整形されたメッセージデータ
  def build_message_data(message, include_body, include_html)
    headers = message.payload&.headers || []

    data = {
      id: message.id,
      thread_id: message.thread_id,
      date: find_header(headers, "Date"),
      from: find_header(headers, "From"),
      to: find_header(headers, "To"),
      subject: find_header(headers, "Subject"),
      snippet: message.snippet,
      labels: message.label_ids || []
    }

    if include_body
      plain_text = extract_body_with_encoding(message.payload, "text/plain")
      if include_html
        html = extract_body_with_encoding(message.payload, "text/html")
        data[:body] = { plain_text: plain_text, html: html }
      else
        has_html = body_has_type?(message.payload, "text/html")
        data[:body] = { plain_text: plain_text, has_html: has_html }
      end
    end

    data
  end

  # ヘッダーから指定した名前の値を取得する
  #
  # @param headers [Array<Google::Apis::GmailV1::MessagePartHeader>] ヘッダー配列
  # @param name [String] ヘッダー名
  # @return [String, nil] ヘッダー値
  def find_header(headers, name)
    headers.find { |h| h.name.casecmp?(name) }&.value
  end

  # メッセージ本文を抽出する
  #
  # @param payload [Google::Apis::GmailV1::MessagePart] メッセージペイロード
  # @param mime_type [String] 取得したいMIMEタイプ
  # @return [String] デコードされた本文
  def extract_body(payload, mime_type)
    return "" if payload.nil?

    # 単一パートの場合
    return decode_body(payload.body.data) if payload.mime_type == mime_type && payload.body&.data

    # マルチパートの場合
    if payload.parts
      # 指定されたMIMEタイプのパートを探す
      target_part = payload.parts.find { |p| p.mime_type == mime_type }
      return decode_body(target_part.body.data) if target_part&.body&.data

      # ネストされたパートを再帰的に探す
      payload.parts.each do |part|
        result = extract_body(part, mime_type)
        return result unless result.empty?
      end
    end

    ""
  end

  # 指定したMIMEタイプの本文が存在するか確認する
  #
  # @param payload [Google::Apis::GmailV1::MessagePart] メッセージペイロード
  # @param mime_type [String] 確認したいMIMEタイプ
  # @return [Boolean]
  def body_has_type?(payload, mime_type)
    return false if payload.nil?

    return true if payload.mime_type == mime_type && payload.body&.data

    return false unless payload.parts

    payload.parts.any? do |part|
      (part.mime_type == mime_type && part.body&.data) || body_has_type?(part, mime_type)
    end
  end

  # Base64 URL-safeデコードを行う（既にデコード済みの場合はそのまま返す）
  #
  # @param encoded_data [String] エンコードされたデータ
  # @return [String] デコードされた文字列
  def decode_body(encoded_data)
    return "" if encoded_data.nil? || encoded_data.empty?

    Base64.urlsafe_decode64(encoded_data).force_encoding("UTF-8")
  rescue ArgumentError
    # Gmail APIが既にデコード済みのデータを返す場合がある
    encoded_data.force_encoding("UTF-8")
  end

  # Content-Typeヘッダーからcharsetを抽出する
  #
  # @param content_type [String, nil] Content-Typeヘッダー値
  # @return [String, nil] charset値
  def extract_charset(content_type)
    return nil if content_type.nil?

    match = content_type.match(/charset=["']?([^"';\s]+)["']?/i)
    match&.[](1)
  end

  # エンコーディングを考慮してメッセージ本文を抽出する
  #
  # @param payload [Google::Apis::GmailV1::MessagePart] メッセージペイロード
  # @param mime_type [String] 取得したいMIMEタイプ
  # @return [String] デコードされた本文
  def extract_body_with_encoding(payload, mime_type)
    return "" if payload.nil?

    # 単一パートの場合
    if payload.mime_type == mime_type && payload.body&.data
      return decode_body_with_encoding(payload.body.data, payload.headers)
    end

    # マルチパートの場合
    if payload.parts
      target_part = payload.parts.find { |p| p.mime_type == mime_type }
      return decode_body_with_encoding(target_part.body.data, target_part.headers) if target_part&.body&.data

      payload.parts.each do |part|
        result = extract_body_with_encoding(part, mime_type)
        return result unless result.empty?
      end
    end

    ""
  end

  # エンコーディングを考慮してBase64デコードを行う（既にデコード済みの場合も対応）
  #
  # @param encoded_data [String] エンコードされたデータ
  # @param headers [Array<Google::Apis::GmailV1::MessagePartHeader>, nil] ヘッダー配列
  # @return [String] デコードされた文字列
  def decode_body_with_encoding(encoded_data, headers)
    return "" if encoded_data.nil? || encoded_data.empty?

    content_type = find_header(headers || [], "Content-Type")
    charset = extract_charset(content_type) || "UTF-8"

    # Base64デコードを試みる。失敗した場合は既にデコード済みとみなす
    decoded = begin
      Base64.urlsafe_decode64(encoded_data)
    rescue ArgumentError
      encoded_data.dup
    end

    decoded.encode("UTF-8", charset, invalid: :replace, undef: :replace)
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    decoded.force_encoding("UTF-8")
  end
end

# コマンドライン引数を解析する
#
# @return [Hash] オプション
def parse_options
  options = {
    query: nil,
    max_results: GmailSearcher::DEFAULT_MAX_RESULTS,
    include_body: true,
    include_html: false
  }

  parser = build_option_parser(options)
  parser.parse!
  validate_required_options(options, parser)

  options
end

# OptionParserを構築する
#
# @param options [Hash] オプションハッシュ
# @return [OptionParser]
def build_option_parser(options)
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby gmail_searcher.rb [options]"

    define_required_options(opts, options)
    define_optional_options(opts, options)
    define_examples(opts)
  end
end

def define_required_options(opts, options)
  opts.separator ""
  opts.separator "Required options:"

  opts.on("--query=QUERY", "Gmail search query (same syntax as Gmail search box)") do |v|
    options[:query] = v
  end
end

def define_optional_options(opts, options)
  opts.separator ""
  opts.separator "Optional options:"

  opts.on("--max-results=N", Integer, "Maximum number of results (default: 10)") do |v|
    options[:max_results] = v
  end

  opts.on("--no-body", "Don't include message body (faster)") do
    options[:include_body] = false
  end

  opts.on("--include-html", "Include HTML body content (default: flag only)") do
    options[:include_html] = true
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end

def define_examples(opts)
  opts.separator ""
  opts.separator "Examples:"
  opts.separator "  ruby gmail_searcher.rb --query='from:apple.com AirTag'"
  opts.separator "  ruby gmail_searcher.rb --query='from:amazon.co.jp after:2025/01/01' --max-results=5"
  opts.separator "  ruby gmail_searcher.rb --query='subject:invoice' --no-body"
  opts.separator "  ruby gmail_searcher.rb --query='from:amazon.co.jp' --include-html"
  opts.separator ""
  opts.separator "Gmail query operators:"
  opts.separator "  from:sender        - Messages from specific sender"
  opts.separator "  to:recipient       - Messages to specific recipient"
  opts.separator "  subject:word       - Messages with word in subject"
  opts.separator "  after:YYYY/MM/DD   - Messages after date"
  opts.separator "  before:YYYY/MM/DD  - Messages before date"
  opts.separator "  has:attachment     - Messages with attachments"
  opts.separator "  label:name         - Messages with specific label"
end

def validate_required_options(options, parser)
  return if options[:query]

  warn "Error: --query is required"
  warn ""
  warn parser
  exit 1
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  begin
    options = parse_options
    searcher = GmailSearcher.new
    searcher.search(
      query: options[:query],
      max_results: options[:max_results],
      include_body: options[:include_body],
      include_html: options[:include_html]
    )
  rescue StandardError => e
    puts JSON.generate({ error: e.message })
    exit 1
  end
end
