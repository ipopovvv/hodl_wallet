# frozen_string_literal: true

require_relative '../lib/script_logger'

module Services
  # class HttpClient
  class HttpClient
    extend Dry::Configurable
    include ScriptLogger

    class ConnectionError < StandardError; end
    class TimeoutError < StandardError; end
    class ParsingError < StandardError; end

    setting :base_url, default: ENV['MEMPOOL_API_URL']
    setting :timeout, default: 5
    setting :headers, default: { 'Content-Type' => 'application/json' }

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.client
      Faraday.new(url: config.base_url, headers: config.headers, request: { timeout: config.timeout }) do |conn|
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
      end
    rescue Faraday::ConnectionFailed => e
      log_error("Connection failed: #{e.message}")
      raise ConnectionError, "Could not connect to #{config.base_url}"
    rescue Faraday::TimeoutError => e
      log_error("Request timed out after #{config.timeout} seconds: #{e.message}")
      raise TimeoutError, "Request timed out after #{config.timeout} seconds"
    rescue Faraday::ParsingError => e
      log_error("Response parsing failed: #{e.message}")
      raise ParsingError, 'Could not parse response'
    rescue StandardError => e
      log_error("Unexpected error: #{e.class} - #{e.message}")
      raise ConnectionError, 'Unexpected error occurred'
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
