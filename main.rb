require 'dotenv/load'
require_relative 'lib/wallet'
require_relative 'lib/balance_checker'
require_relative 'lib/transaction_sender'

puts "Bitcoin Wallet"
puts "1. Сгенерировать новый кошелек"
puts "2. Показать баланс"
puts "3. Отправить BTC"
puts "Выберите действие:"

choice = gets.chomp

case choice
when '1'
  Wallet.generate
when '2'
  BalanceChecker.check_balance
when '3'
  TransactionSender.send_btc
else
  puts "Неверный выбор"
end
