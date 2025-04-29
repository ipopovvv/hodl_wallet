require_relative 'wallet'

module BalanceChecker

  def self.check_balance
    new.balance
  end

  def self.new
    address = Wallet.load.to_p2wpkh
    Checker.new(address)
  end

  class Checker
    def initialize(address)
      @address = address
    end

    def balance
      utxos = fetch_utxos

      if utxos.empty?
        log("Balance: 0 sBTC")
      else
        log("Balance: #{calculate_balance(utxos)} sBTC")
      end
    end

    private

    def fetch_utxos
      response = Faraday.get("#{ENV['MEMPOOL_API_URL']}/address/#{@address}/utxo")

      if response.success?
        JSON.parse(response.body)
      else
        log("Error fetching UTXOs: #{response.status} #{response.body}")
        []
      end
    rescue StandardError => e
      log("Error fetching UTXOs: #{e.message}")
      []
    end

    def calculate_balance(utxos)
      sats = utxos.sum { |utxo| utxo["value"] }
      (sats.to_f / 100_000_000).round(8)
    end

    def log(message)
      puts message
    end
  end
end
