# frozen_string_literal: true

require_relative '../utils/script_logger'

# Main module Wallet
module Wallet
  KEYS_DIR = 'keys'

  # Class for wallet generation operations
  class Generator
    include ScriptLogger

    # Generates a new Bitcoin key, saves it, updates .env, and returns the Taproot address
    def call
      Bitcoin.chain_params = :signet

      @key = Bitcoin::Key.generate
      @key_wif = @key.to_wif

      save_private_key_to_file
      update_env_file_with_key

      address = @key.to_p2tr

      log_generation_result(address)

      address
    rescue StandardError => e
      log_error "Something went wrong while generating the Wallet: #{e.message}"
    end

    private

    def save_private_key_to_file
      Dir.mkdir(KEYS_DIR) unless Dir.exist?(KEYS_DIR)
      file_name = ENV['KEY_FILE_NAME'] || 'private_key'
      File.write(File.join(KEYS_DIR, file_name), @key_wif)
    end

    def update_env_file_with_key
      env_path = File.expand_path('../.env', __dir__)
      return unless File.exist?(env_path)

      lines = File.readlines(env_path)
      updated_lines = lines.map do |line|
        line.start_with?('PRIVATE_KEY_WIF=') ? "PRIVATE_KEY_WIF='#{@key_wif}'\n" : line
      end
      File.write(env_path, updated_lines.join)
    end

    def log_generation_result(address)
      log_info('Wallet generated')
      log_info("Address: #{address}")
      log_info("Private Key (WIF): #{@key_wif}")
      log_info('Store this private key securely. It will not be saved automatically.')
    end
  end

  # Class for loading existing wallets
  class Loader
    include ScriptLogger

    attr_reader :key

    def initialize
      Bitcoin.chain_params = :signet

      wif = ENV['PRIVATE_KEY_WIF']
      unless wif && !wif.strip.empty?
        log_info('Environment variable PRIVATE_KEY_WIF is missing. Please check set it in your .env file MANUALLY.')
        return
      end

      @key = Bitcoin::Key.from_wif(wif)
    rescue StandardError => e
      log_error "Invalid WIF format: #{e.message}"
      raise
    end
  end
end
