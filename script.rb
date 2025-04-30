# frozen_string_literal: true

require 'dotenv/load'
require 'faraday'
require 'json'
require 'bitcoin'
require 'rubocop'
require_relative 'lib/wallet'
require_relative 'lib/balance_checker'
require_relative 'lib/transaction_sender'
require_relative 'lib/script_logger'

# Main class for Script
class Script
  include ScriptLogger

  def self.call
    new.run
  end

  # rubocop:disable Metrics/MethodLength
  # Main loop for running the wallet operations menu
  # allowing the user to generate a wallet, check balance, send BTC, or exit
  def run
    loop do
      print_menu
      case gets.chomp
      when '1'
        Wallet.generate
        return
      when '2'
        BalanceChecker.check_balance
      when '3'
        TransactionSender.send_btc
      when '4'
        break
      else
        log_info('Invalid choice. Please try again.')
      end
    rescue StandardError => e
      log_error("Something went wrong. Trace: #{e.message}")
    end
  end
  # rubocop:enable Metrics/MethodLength

  private

  def print_menu
    puts "\nBitcoin Wallet"
    puts '1. Generate new wallet'
    puts '2. Show balance'
    puts '3. Send BTC'
    puts '4. Exit'
    print 'Choose an option: '
  end
end

Script.call
