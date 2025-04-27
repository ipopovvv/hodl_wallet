require 'dotenv/load'
require_relative 'lib/wallet'
require_relative 'lib/bitcoin_client'
require_relative 'lib/utxo_fetcher'
require_relative 'lib/transaction_service'

puts "Bitcoin Wallet"
puts "1. Сгенерировать новый кошелек"
puts "2. Показать баланс"
puts "3. Отправить BTC"
puts "Выберите действие:"

choice = gets.chomp

case choice
when '1'
  # TODO
when '2'
  # TODO
when '3'
  # TODO
else
  puts "Неверный выбор"
end
