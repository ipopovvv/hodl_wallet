require 'dotenv/load'
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
      when '2'
        BalanceChecker.check_balance
      when '3'
        TransactionSender.send_btc
      when '4'
        break
      else
        puts "Invalid choice. Please try again."
      end
    end
  end

  private

  def print_menu
    puts "\nBitcoin Wallet"
    puts "1. Generate new wallet"
    puts "2. Show balance"
    puts "3. Send BTC"
    puts "4. Exit"
    print "Choose an option: "
  end
end

Script.call