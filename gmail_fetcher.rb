#!/usr/bin/env ruby
# frozen_string_literal: true

require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"
require "json"
require "optparse"
require "base64"

# GmailFetcher fetches a single Gmail message by ID
class GmailFetcher
  APPLICATION_NAME = "Gmail Fetcher"
  CREDENTIALS_DIR = File.join(Dir.home, ".credentials")
  TOKEN_PATH = File.join(CREDENTIALS_DIR, "gmail-readonly-token.yaml")
  SCOPE = Google::Apis::GmailV1::AUTH_GMAIL_READONLY
  VALID_FORMATS = %w[full minimal metadata raw].freeze

  # GmailFetcherを初期化する
  #
  # @raise [RuntimeError] 認証情報が存在しない場合
  def initialize
    validate_credentials
    @service = Google::Apis::GmailV1::GmailService.new
    @service.client_options.application_name = APPLICATION_NAME
    @service.authorization = authorize
  end

  # メッセージを取得してJSON形式で出力する
  #
  # @param message_id [String] メッセージID
  # @param format [String] レスポンス形式（full, minimal, metadata, raw）
  # @return [void]
  def fetch(message_id:, format: "full")
    message = @service.get_user_message("me", message_id, format: format)
    result = build_message_data(message, format)

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

  # メッセージデータをハッシュに整形する
  #
  # @param message [Google::Apis::GmailV1::Message] メッセージ
  # @param format [String] レスポンス形式
  # @return [Hash] 整形されたメッセージデータ
  def build_message_data(message, format)
    headers = message.payload&.headers || []

    data = {
      id: message.id,
      thread_id: message.thread_id,
      date: find_header(headers, "Date"),
      from: find_header(headers, "From"),
      to: find_header(headers, "To"),
      subject: find_header(headers, "Subject"),
      labels: message.label_ids || []
    }

    if format == "full"
      data[:body] = {
        plain_text: extract_body_with_encoding(message.payload, "text/plain"),
        html: extract_body_with_encoding(message.payload, "text/html")
      }
      data[:attachments] = extract_attachments(message.payload)
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
      target_part = payload.parts.find { |p| p.mime_type == mime_type }
      return decode_body(target_part.body.data) if target_part&.body&.data

      payload.parts.each do |part|
        result = extract_body(part, mime_type)
        return result unless result.empty?
      end
    end

    ""
  end

  # 添付ファイル情報を抽出する
  #
  # @param payload [Google::Apis::GmailV1::MessagePart] メッセージペイロード
  # @return [Array<Hash>] 添付ファイル情報の配列
  def extract_attachments(payload)
    return [] if payload.nil? || payload.parts.nil?

    attachments = []

    payload.parts.each do |part|
      if part.filename && !part.filename.empty?
        attachments << {
          filename: part.filename,
          mime_type: part.mime_type,
          size: part.body&.size
        }
      end

      # ネストされたパートも確認
      attachments.concat(extract_attachments(part)) if part.parts
    end

    attachments
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
    message_id: nil,
    format: "full"
  }

  parser = build_option_parser(options)
  parser.parse!
  validate_required_options(options, parser)
  validate_format(options[:format])

  options
end

# OptionParserを構築する
#
# @param options [Hash] オプションハッシュ
# @return [OptionParser]
def build_option_parser(options)
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby gmail_fetcher.rb [options]"

    opts.separator ""
    opts.separator "Required options:"

    opts.on("--message-id=ID", "Gmail message ID") do |v|
      options[:message_id] = v
    end

    opts.separator ""
    opts.separator "Optional options:"

    opts.on("--format=FORMAT", "Response format: full (default), minimal, metadata, raw") do |v|
      options[:format] = v
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end

    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  ruby gmail_fetcher.rb --message-id='18abc123def456'"
    opts.separator "  ruby gmail_fetcher.rb --message-id='18abc123def456' --format=metadata"
  end
end

def validate_required_options(options, parser)
  return if options[:message_id]

  warn "Error: --message-id is required"
  warn ""
  warn parser
  exit 1
end

def validate_format(format)
  return if GmailFetcher::VALID_FORMATS.include?(format)

  warn "Error: Invalid format '#{format}'. Valid formats: #{GmailFetcher::VALID_FORMATS.join(', ')}"
  exit 1
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  begin
    options = parse_options
    fetcher = GmailFetcher.new
    fetcher.fetch(
      message_id: options[:message_id],
      format: options[:format]
    )
  rescue StandardError => e
    puts JSON.generate({ error: e.message })
    exit 1
  end
end
