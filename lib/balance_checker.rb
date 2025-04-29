require 'net/http'
require 'json'
require_relative 'wallet'

module BalanceChecker
  MEMPOOL_API_URL = 'https://mempool.space/signet/api'

  def self.check_balance
    key = Wallet.load
    address = key.to_p2wpkh

    url = URI("#{MEMPOOL_API_URL}/address/#{address}/utxo")
    response = Net::HTTP.get(url)
    utxos = JSON.parse(response)

    if utxos.empty?
      puts "Balance: 0 BTC"
      return
    end

    balance_sats = utxos.sum { |utxo| utxo["value"] }
    balance_btc = balance_sats.to_f / 100_000_000

    puts "Balance: #{balance_btc} BTC"
  end
end
