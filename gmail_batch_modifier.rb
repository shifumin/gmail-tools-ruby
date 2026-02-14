#!/usr/bin/env ruby
# frozen_string_literal: true

require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"
require "json"
require "optparse"

# GmailBatchModifier modifies labels on messages matching a query using Gmail API
class GmailBatchModifier
  APPLICATION_NAME = "Gmail Batch Modifier"
  CREDENTIALS_DIR = File.join(Dir.home, ".credentials")
  TOKEN_PATH = File.join(CREDENTIALS_DIR, "gmail-modify-token.yaml")
  SCOPE = Google::Apis::GmailV1::AUTH_GMAIL_MODIFY
  MAX_BATCH_SIZE = 100

  # GmailBatchModifierを初期化する
  #
  # @raise [RuntimeError] 認証情報が存在しない場合
  def initialize
    validate_credentials
    @service = Google::Apis::GmailV1::GmailService.new
    @service.client_options.application_name = APPLICATION_NAME
    @service.authorization = authorize
  end

  # クエリに一致するメッセージのラベルをバッチ変更する
  #
  # @param query [String] Gmail検索クエリ
  # @param add_labels [Array<String>] 追加するラベルIDリスト
  # @param remove_labels [Array<String>] 削除するラベルIDリスト
  # @param max_results [Integer, nil] 処理する最大メッセージ数（nilの場合は全件）
  # @param dry_run [Boolean] trueの場合、実際には変更しない
  # @return [void]
  def modify(query:, add_labels: [], remove_labels: [], max_results: nil, dry_run: false)
    @query = query
    @add_labels = add_labels
    @remove_labels = remove_labels

    messages = fetch_message_ids(max_results)

    if messages.empty?
      puts JSON.pretty_generate({ total_count: 0, message: "No messages found." })
      return
    end

    if dry_run
      puts JSON.pretty_generate({
                                  dry_run: true, query: @query,
                                  total_count: messages.size, message_ids: messages.map(&:id)
                                })
      return
    end

    modified, failed_batches = modify_messages_in_batches(messages)
    puts JSON.pretty_generate(build_summary(messages.size, modified, failed_batches))
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

    raise "No credentials found. Please run 'ruby gmail_authenticator.rb --scope=modify' first to authenticate."
  end

  # クエリに一致するメッセージIDリストを取得する
  #
  # @param max_results [Integer, nil] 最大取得件数（nilの場合は全件）
  # @return [Array<Google::Apis::GmailV1::Message>] メッセージリスト
  def fetch_message_ids(max_results)
    messages = []
    page_token = nil

    loop do
      page_size = max_results ? [max_results - messages.size, 500].min : 500

      response = @service.list_user_messages(
        "me",
        q: @query,
        max_results: page_size,
        page_token: page_token
      )

      break if response.messages.nil? || response.messages.empty?

      messages.concat(response.messages)
      break if max_results && messages.size >= max_results
      break if response.next_page_token.nil?

      page_token = response.next_page_token
    end

    max_results ? messages.take(max_results) : messages
  end

  # メッセージをバッチでラベル変更する
  #
  # @param messages [Array<Google::Apis::GmailV1::Message>] メッセージリスト
  # @return [Array(Integer, Array<Hash>)] 変更した件数と失敗したバッチの配列
  def modify_messages_in_batches(messages)
    modified = 0
    failed_batches = []

    messages.each_slice(MAX_BATCH_SIZE).with_index do |batch, index|
      modify_batch(batch)
      modified += batch.size
      warn "\rModified: #{modified}/#{messages.size}"
    rescue Google::Apis::Error => e
      failed_batches << { batch_index: index, size: batch.size, error: e.message }
      warn "Batch #{index} failed: #{e.message}"
    end

    [modified, failed_batches]
  end

  # バッチでメッセージのラベルを変更する
  #
  # @param messages [Array<Google::Apis::GmailV1::Message>] メッセージリスト
  # @return [void]
  def modify_batch(messages)
    body = Google::Apis::GmailV1::BatchModifyMessagesRequest.new(
      ids: messages.map(&:id),
      add_label_ids: @add_labels,
      remove_label_ids: @remove_labels
    )
    @service.batch_modify_messages("me", body)
  end

  # 結果サマリーを構築する
  #
  # @param total [Integer] 総件数
  # @param modified [Integer] 変更した件数
  # @param failed_batches [Array<Hash>] 失敗したバッチの情報
  # @return [Hash] サマリー
  def build_summary(total, modified, failed_batches)
    {
      query: @query,
      total_count: total,
      modified_count: modified,
      add_labels: @add_labels,
      remove_labels: @remove_labels,
      failed_batches: failed_batches,
      success: failed_batches.empty?
    }
  end
end

# コマンドライン引数を解析する
#
# @return [Hash] オプション
def parse_options
  options = {
    query: nil,
    add_labels: [],
    remove_labels: [],
    max_results: nil,
    dry_run: false
  }

  parser = build_option_parser(options)
  parser.parse!

  validate_options(options)
  options
end

# OptionParserを構築する
#
# @param options [Hash] オプションハッシュ
# @return [OptionParser]
def build_option_parser(options)
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby gmail_batch_modifier.rb --query=QUERY [options]"

    define_options(opts, options)
    define_examples(opts)
  end
end

def define_options(opts, options)
  opts.separator ""
  opts.separator "Options:"

  opts.on("--query=QUERY", "Gmail search query (required)") do |v|
    options[:query] = v
  end

  opts.on("--remove-labels=LABELS", "Comma-separated label IDs to remove (e.g., INBOX,UNREAD)") do |v|
    options[:remove_labels] = v.split(",").map(&:strip)
  end

  opts.on("--add-labels=LABELS", "Comma-separated label IDs to add") do |v|
    options[:add_labels] = v.split(",").map(&:strip)
  end

  opts.on("--max-results=N", Integer, "Maximum number of messages to process (default: all)") do |v|
    options[:max_results] = v
  end

  opts.on("--dry-run", "Preview messages without modifying") do
    options[:dry_run] = true
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end

def define_examples(opts)
  opts.separator ""
  opts.separator "Examples:"
  opts.separator "  ruby gmail_batch_modifier.rb --query='category:social is:unread' --remove-labels=INBOX,UNREAD"
  opts.separator "  ruby gmail_batch_modifier.rb --query='category:promotions is:unread' --remove-labels=INBOX,UNREAD"
  opts.separator "  ruby gmail_batch_modifier.rb --query='from:noreply@example.com' --remove-labels=INBOX --dry-run"
end

# コマンドラインオプションを検証する
#
# @param options [Hash] オプション
# @raise [RuntimeError] 必須オプションが不足している場合
# @return [void]
def validate_options(options)
  raise "Error: --query is required." if options[:query].nil? || options[:query].empty?

  return unless options[:add_labels].empty? && options[:remove_labels].empty?

  raise "Error: --add-labels or --remove-labels (or both) is required."
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  begin
    options = parse_options
    modifier = GmailBatchModifier.new
    modifier.modify(
      query: options[:query],
      add_labels: options[:add_labels],
      remove_labels: options[:remove_labels],
      max_results: options[:max_results],
      dry_run: options[:dry_run]
    )
  rescue StandardError => e
    puts JSON.generate({ error: e.message })
    exit 1
  end
end
