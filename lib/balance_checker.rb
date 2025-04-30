# frozen_string_literal: true

require_relative 'wallet'
require_relative 'script_logger'

# module BalanceChecker
module BalanceChecker
  def self.check_balance
    new.balance
  end

  def self.new
    address = Wallet.load.to_p2tr
    Checker.new(address)
  end

  # class Checker for checking balance
  class Checker
    include ScriptLogger

    def initialize(address)
      @address = address
    end

    def balance
      utxos = fetch_utxos

      if utxos.empty?
        log_info('Balance: 0 sBTC')
      else
        log_info("Balance: #{calculate_balance(utxos)} sBTC")
      end
    end

    private

    def fetch_utxos
      response = Faraday.get("#{ENV['MEMPOOL_API_URL']}/address/#{@address}/utxo")

      if response.success?
        JSON.parse(response.body)
      else
        log_info("Error fetching UTXOs: #{response.status} #{response.body}")
        []
      end
    rescue StandardError => e
      log_error("Error fetching UTXOs: #{e.message}")
      []
    end

    def calculate_balance(utxos)
      sats = utxos.sum { |utxo| utxo['value'] }
      (sats.to_f / 100_000_000).round(8)
    end
  end
end
