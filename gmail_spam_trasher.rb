#!/usr/bin/env ruby
# frozen_string_literal: true

require "google/apis/gmail_v1"
require "googleauth"
require "googleauth/stores/file_token_store"
require "json"
require "optparse"

# GmailSpamTrasher moves spam messages to trash using Gmail API
class GmailSpamTrasher
  APPLICATION_NAME = "Gmail Spam Trasher"
  CREDENTIALS_DIR = File.join(Dir.home, ".credentials")
  TOKEN_PATH = File.join(CREDENTIALS_DIR, "gmail-modify-token.yaml")
  SCOPE = Google::Apis::GmailV1::AUTH_GMAIL_MODIFY
  DEFAULT_MAX_RESULTS = 500
  MAX_BATCH_SIZE = 100

  # GmailSpamTrasherを初期化する
  #
  # @raise [RuntimeError] 認証情報が存在しない場合
  def initialize
    validate_credentials
    @service = Google::Apis::GmailV1::GmailService.new
    @service.client_options.application_name = APPLICATION_NAME
    @service.authorization = authorize
  end

  # スパムメッセージをゴミ箱に移動する
  #
  # @param max_results [Integer] 処理する最大メッセージ数
  # @param dry_run [Boolean] trueの場合、実際にはゴミ箱に移動しない
  # @param batch_size [Integer] バッチあたりのメッセージ数
  # @return [void]
  def trash_spam(max_results: DEFAULT_MAX_RESULTS, dry_run: false, batch_size: MAX_BATCH_SIZE)
    spam_messages = fetch_spam_message_ids(max_results)

    if spam_messages.empty?
      puts JSON.pretty_generate({ spam_count: 0, message: "No spam messages found." })
      return
    end

    if dry_run
      puts JSON.pretty_generate({ dry_run: true, spam_count: spam_messages.size, message_ids: spam_messages.map(&:id) })
      return
    end

    trashed, failed_batches = trash_messages_in_batches(spam_messages, batch_size)
    puts JSON.pretty_generate(build_summary(spam_messages.size, trashed, failed_batches))
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

  # スパムメッセージIDリストを取得する
  #
  # @param max_results [Integer] 最大取得件数
  # @return [Array<Google::Apis::GmailV1::Message>] メッセージリスト
  def fetch_spam_message_ids(max_results)
    messages = []
    page_token = nil

    loop do
      remaining = max_results - messages.size
      page_size = [remaining, 500].min

      response = @service.list_user_messages(
        "me",
        label_ids: ["SPAM"],
        include_spam_trash: true,
        max_results: page_size,
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

  # メッセージをバッチでゴミ箱に移動する
  #
  # @param messages [Array<Google::Apis::GmailV1::Message>] メッセージリスト
  # @param batch_size [Integer] バッチあたりのメッセージ数
  # @return [Array(Integer, Array<Hash>)] ゴミ箱に移動した件数と失敗したバッチの配列
  def trash_messages_in_batches(messages, batch_size)
    effective_batch_size = [batch_size, MAX_BATCH_SIZE].min
    trashed = 0
    failed_batches = []

    messages.each_slice(effective_batch_size).with_index do |batch, index|
      trash_batch(batch)
      trashed += batch.size
      warn "\rTrashed: #{trashed}/#{messages.size}"
    rescue Google::Apis::Error => e
      failed_batches << { batch_index: index, size: batch.size, error: e.message }
      warn "Batch #{index} failed: #{e.message}"
    end

    [trashed, failed_batches]
  end

  # バッチでメッセージをゴミ箱に移動する
  #
  # @param messages [Array<Google::Apis::GmailV1::Message>] メッセージリスト
  # @return [void]
  def trash_batch(messages)
    body = Google::Apis::GmailV1::BatchModifyMessagesRequest.new(
      ids: messages.map(&:id),
      add_label_ids: ["TRASH"],
      remove_label_ids: ["SPAM"]
    )
    @service.batch_modify_messages("me", body)
  end

  # 結果サマリーを構築する
  #
  # @param total [Integer] 総スパム件数
  # @param trashed [Integer] ゴミ箱に移動した件数
  # @param failed_batches [Array<Hash>] 失敗したバッチの情報
  # @return [Hash] サマリー
  def build_summary(total, trashed, failed_batches)
    {
      spam_count: total,
      trashed_count: trashed,
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
    max_results: GmailSpamTrasher::DEFAULT_MAX_RESULTS,
    dry_run: false,
    batch_size: GmailSpamTrasher::MAX_BATCH_SIZE
  }

  parser = build_option_parser(options)
  parser.parse!

  options
end

# OptionParserを構築する
#
# @param options [Hash] オプションハッシュ
# @return [OptionParser]
def build_option_parser(options)
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby gmail_spam_trasher.rb [options]"

    define_options(opts, options)
    define_examples(opts)
  end
end

def define_options(opts, options)
  opts.separator ""
  opts.separator "Options:"

  opts.on("--max-results=N", Integer, "Maximum number of spam messages to process (default: 500)") do |v|
    options[:max_results] = v
  end

  opts.on("--dry-run", "Preview spam messages without trashing") do
    options[:dry_run] = true
  end

  opts.on("--batch-size=N", Integer, "Messages per batch API call (default: 100, max: 100)") do |v|
    options[:batch_size] = v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end

def define_examples(opts)
  opts.separator ""
  opts.separator "Examples:"
  opts.separator "  ruby gmail_spam_trasher.rb --dry-run"
  opts.separator "  ruby gmail_spam_trasher.rb --max-results=10"
  opts.separator "  ruby gmail_spam_trasher.rb --max-results=1000"
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  begin
    options = parse_options
    trasher = GmailSpamTrasher.new
    trasher.trash_spam(
      max_results: options[:max_results],
      dry_run: options[:dry_run],
      batch_size: options[:batch_size]
    )
  rescue StandardError => e
    puts JSON.generate({ error: e.message })
    exit 1
  end
end
