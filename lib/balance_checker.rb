# frozen_string_literal: true

require_relative 'wallet'
require_relative 'script_logger'

# module BalanceChecker
module BalanceChecker
  # class Checker
  class Checker
    include ScriptLogger

    def initialize(client)
      @address = load_wallet
      @client = client
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

    def load_wallet
      Wallet::Loader.new.key.to_p2tr
    end

    def fetch_utxos
      log_info("Fetching utxos for #{@address}...")
      @client.get("/signet/api/address/#{@address}/utxo").body
    end

    def calculate_balance(utxos)
      sats = utxos.sum { |utxo| utxo['value'] }
      (sats.to_f / 100_000_000).round(8)
    end
  end
end
