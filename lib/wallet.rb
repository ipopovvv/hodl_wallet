module Wallet
  KEYS_DIR='keys'

  def self.generate
    Bitcoin.chain_params = :signet

    key = Bitcoin::Key.generate
    key_wif = key.to_wif

    save_private_key_to_file(key_wif)
    update_env_file_with_key(key_wif)

    address = key.to_p2wpkh

    log_generation_result(address, key_wif)

    address
  rescue StandardError => e
    Wallet.log "Something went wrong while generate the Wallet: #{e.message}"
    return
  end

  def self.save_private_key_to_file(key_wif)
    Dir.mkdir(KEYS_DIR) unless Dir.exist?(KEYS_DIR)
    file_name = ENV['KEY_FILE_NAME'] || 'private_key'
    File.write(File.join(KEYS_DIR, file_name), key_wif)
  end

  def self.update_env_file_with_key(key_wif)
    env_path = File.expand_path('../.env', __dir__)
    return unless File.exist?(env_path)

    lines = File.readlines(env_path)
    updated_lines = lines.map do |line|
      line.start_with?('PRIVATE_KEY_WIF=') ? "PRIVATE_KEY_WIF='#{key_wif}'\n" : line
    end
    File.write(env_path, updated_lines.join)
  end

  def self.log_generation_result(address, key_wif)
    log("Wallet generated")
    log("Address: #{address}")
    log("Private Key (WIF): #{key_wif}")
    log("Store this private key securely. It will not be saved automatically.")
  end

  def self.load
    Bitcoin.chain_params = :signet

    wif = ENV['PRIVATE_KEY_WIF']
    unless wif && !wif.strip.empty?
      log "Environment variable PRIVATE_KEY_WIF is missing. Please check set it in your .env file MANUALLY."
      return
    end

    Loader.new(wif).key
  end

  def self.log(message)
    puts message
  end

  class Loader
    attr_reader :key

    def initialize(wif)
      @key = Bitcoin::Key.from_wif(wif)
    rescue StandardError => e
      Wallet.log "Invalid WIF format: #{e.message}"
      return
    end
  end
end
