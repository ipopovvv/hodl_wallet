require 'faraday'
require 'json'
require 'bitcoin'
require_relative 'wallet'

module TransactionSender
  MEMPOOL_API_URL = 'https://mempool.space/signet/api'
  FEE_SATS = 1_000 # 0.00001 BTC

  def self.send_btc
    print "Enter receiver address: "
    recipient_address = gets.strip

    print "Enter sBTC amount: "
    amount_btc = gets.strip.to_f
    amount_sats = (amount_btc * 100_000_000).to_i

    key = Wallet.load
    address = key.to_p2wpkh

    # All UTXOs
    utxos = fetch_utxos(address)

    # Check balance
    total_sats = utxos.sum { |utxo| utxo["value"] }
    if total_sats < amount_sats + FEE_SATS
      puts "Insufficient funds (including commission)"
      return
    end

    # Build transaction
    tx = Bitcoin::Tx.new

    # Add inputs
    utxos.each do |utxo|
      out_point = Bitcoin::OutPoint.new([utxo["txid"]].pack("H*").reverse.b, utxo["vout"])
      txin = Bitcoin::TxIn.new(out_point: out_point)
      tx.inputs << txin
    end

    # Add output to receiver
    recipient_script = Bitcoin::Script.parse_from_addr(recipient_address)
    txout = Bitcoin::TxOut.new(value: amount_sats, script_pubkey: recipient_script)
    tx.outputs << txout

    # Add change return
    change_sats = total_sats - amount_sats - FEE_SATS
    if change_sats > 0
      change_script = Bitcoin::Script.parse_from_addr(address)
      change_txout = Bitcoin::TxOut.new(value: change_sats, script_pubkey: change_script)
      tx.outputs << change_txout
    end

    # Signing input
    utxos.each_with_index do |utxo, index|
      script_pubkey = Bitcoin::Script.parse_from_addr(address)
      sighash = tx.sighash_for_input(index,
                                     script_pubkey,
                                     opts: { amount: utxo["value"] },
                                     hash_type: Bitcoin::SIGHASH_TYPE[:all],
                                     sig_version: :witness_v0
      )

      signature = key.sign(sighash) + [Bitcoin::SIGHASH_TYPE[:all]].pack("C")

      tx.inputs[index].script_witness.stack << signature
      tx.inputs[index].script_witness.stack << key.pubkey
    end

    puts "Final inputs list:"
    tx.inputs.each_with_index do |input, index|
      puts "Input #{index + 1}: #{input.out_point.txid} - #{input.out_point.index}"
    end

    # Broadcast the transaction
    tx_hex = tx.to_hex
    broadcast(tx_hex)

    puts "Transaction broadcast sent!"
  end

  def self.fetch_utxos(address)
    response = Faraday.get("#{MEMPOOL_API_URL}/address/#{address}/utxo")
    utxos = JSON.parse(response.body)
    puts "UTXOs: #{utxos}"

    # Check confirmed UTXOs
    utxos.each do |utxo|
      if utxo["status"]["confirmed"]
        puts "UTXO #{utxo["txid"]} confirmed with block #{utxo["status"]["block_height"]}"
      else
        puts "UTXO #{utxo["txid"]} does not confirmed"
      end
    end

    utxos
  end

  def self.broadcast(tx_hex)
    response = Faraday.post("#{MEMPOOL_API_URL}/tx", tx_hex)
    puts "Mempool response: #{response.body}"
  end
end
