# frozen_string_literal: true

require_relative 'wallet'
require_relative 'script_logger'

# module BalanceChecker
module BalanceChecker
  def initialize(client)
    @client = client
  end

  def self.check_balance(client)
    new(client).balance
  end

  def self.new(client)
    address = Wallet.load.to_p2tr
    Checker.new(address, client)
  end

  # class Checker for checking balance
  class Checker
    include ScriptLogger

    def initialize(address, client)
      @address = address
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

    def fetch_utxos
      log_info("Fetching utxos for #{@address}...}")
      @client.get("/signet/api/address/#{@address}/utxo").body
    end

    def calculate_balance(utxos)
      sats = utxos.sum { |utxo| utxo['value'] }
      (sats.to_f / 100_000_000).round(8)
    end
  end
end
