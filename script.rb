require 'dotenv/load'
require 'faraday'
require 'json'
require 'bitcoin'
require_relative 'lib/wallet'
require_relative 'lib/balance_checker'
require_relative 'lib/transaction_sender'

class Script
  def self.call
    new.run
  end

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
        log("Invalid choice. Please try again.")
      end
    rescue StandardError => e
      log("Something went wrong. Trace: #{e.message}")
    end
  end

  private

  def print_menu
    log("\nBitcoin Wallet")
    log("1. Generate new wallet")
    log("2. Show balance")
    log("3. Send BTC")
    log("4. Exit")
    print "Choose an option: "
  end

  def log(message)
    puts message
  end
end

Script.call
