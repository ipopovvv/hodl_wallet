module Wallet
  def self.generate
    Bitcoin.chain_params = :signet

    key = Bitcoin::Key.generate
    address = key.to_p2wpkh

    log("Wallet generated")
    log("Address: #{address}")
    log("Private Key (WIF): #{key.to_wif}")
    log("Store this private key securely. It will not be saved automatically.")

    address
  end

  def self.load
    Bitcoin.chain_params = :signet

    wif = ENV['PRIVATE_KEY_WIF']
    unless wif && !wif.strip.empty?
      log "Environment variable PRIVATE_KEY_WIF is missing. Please set it in your .env file MANUALLY."
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
