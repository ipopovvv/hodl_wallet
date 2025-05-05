# frozen_string_literal: true

require_relative '../../utils/script_logger'

# module Services
module Services
  # class HttpClient
  class HttpClient
    include ScriptLogger
    extend Dry::Configurable

    class ConnectionError < StandardError; end
    class TimeoutError < StandardError; end
    class ParsingError < StandardError; end

    setting :base_url, default: ENV.fetch('MEMPOOL_API_URL', nil)
    setting :timeout, default: 5
    setting :headers, default: { 'Content-Type' => 'application/json' }

    def initialize
      @client = build_client
    end

    attr_reader :client

    private

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def build_client
      Faraday.new(
        url: self.class.config.base_url,
        headers: self.class.config.headers,
        request: { timeout: self.class.config.timeout }
      ) do |conn|
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
      end
    rescue Faraday::ConnectionFailed => e
      log_error("Connection failed: #{e.message}")
      raise ConnectionError, "Could not connect to #{self.class.config.base_url}"
    rescue Faraday::TimeoutError => e
      log_error("Request timed out after #{self.class.config.timeout} seconds: #{e.message}")
      raise TimeoutError, "Request timed out after #{self.class.config.timeout} seconds"
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
