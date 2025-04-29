require_relative 'wallet'

module TransactionSender
  def self.send_btc
    recipient_address = ask_recipient_address
    amount_btc = ask_amount_btc
    amount_sats = btc_to_sats(amount_btc)

    key = Wallet.load
    sender_address = key.to_p2wpkh

    utxos = fetch_utxos(sender_address)
    total_sats = total_balance(utxos)

    dummy_tx = build_transaction(key, utxos, sender_address, recipient_address, amount_sats, 0)
    fee_rate = fetch_fee_rate
    fee = calculate_fee(dummy_tx, fee_rate)

    unless sufficient_funds?(total_sats, amount_sats, fee)
      log("Insufficient funds (including commission)")
      return
    end

    tx = build_transaction(key, utxos, sender_address, recipient_address, amount_sats, fee)
    sign_transaction(tx, utxos, key, sender_address)
    log_inputs(tx)
    broadcast(tx)
  end

  def self.ask_recipient_address
    print "Enter receiver address: "
    gets.strip
  end

  def self.ask_amount_btc
    print "Enter sBTC amount: "
    gets.strip.to_f
  end

  def self.btc_to_sats(amount_btc)
    (amount_btc * 100_000_000).to_i
  end

  def self.fetch_utxos(address)
    response = Faraday.get("#{ENV['MEMPOOL_API_URL']}/address/#{address}/utxo")
    utxos = JSON.parse(response.body)
    log("UTXOs: #{utxos}")

    utxos.each do |utxo|
      if utxo["status"]["confirmed"]
        log("UTXO #{utxo["txid"]} confirmed with block #{utxo["status"]["block_height"]}")
      else
        log("UTXO #{utxo["txid"]} not confirmed")
      end
    end

    utxos
  end

  def self.total_balance(utxos)
    utxos.sum { |utxo| utxo["value"] }
  end

  def self.fetch_fee_rate
    response = Faraday.get("#{ENV['MEMPOOL_API_URL']}/v1/fees/recommended")
    data = JSON.parse(response.body)
    fee_rate = data["fastestFee"]
    log("Fetched fee rate: #{fee_rate} sats/vbyte")
    fee_rate
  end

  def self.calculate_fee(tx, fee_rate)
    vsize = tx.vsize
    fee = vsize * fee_rate
    log("Transaction virtual size: #{vsize} vbytes")
    log("Calculated fee (#{fee_rate} sats/vbyte): #{fee} sats")
    fee
  end

  def self.sufficient_funds?(total_sats, amount_sats, fee)
    total_sats >= amount_sats + fee
  end

  def self.build_transaction(_key, utxos, sender_address, recipient_address, amount_sats, fee)
    tx = Bitcoin::Tx.new

    utxos.each do |utxo|
      out_point = Bitcoin::OutPoint.new([utxo["txid"]].pack("H*").reverse.b, utxo["vout"])
      txin = Bitcoin::TxIn.new(out_point: out_point)
      tx.inputs << txin
    end

    recipient_script = Bitcoin::Script.parse_from_addr(recipient_address)
    txout = Bitcoin::TxOut.new(value: amount_sats, script_pubkey: recipient_script)
    tx.outputs << txout

    add_change_output(tx, utxos, sender_address, amount_sats, fee)

    tx
  end

  def self.add_change_output(tx, utxos, sender_address, amount_sats, fee)
    total_sats = total_balance(utxos)
    change_sats = total_sats - amount_sats - fee
    return if change_sats <= 0

    change_script = Bitcoin::Script.parse_from_addr(sender_address)
    change_txout = Bitcoin::TxOut.new(value: change_sats, script_pubkey: change_script)
    tx.outputs << change_txout
  end

  def self.sign_transaction(tx, utxos, key, sender_address)
    utxos.each_with_index do |utxo, index|
      script_pubkey = Bitcoin::Script.parse_from_addr(sender_address)

      sighash = tx.sighash_for_input(index,
                                     script_pubkey,
                                     opts: { amount: utxo["value"] },
                                     hash_type: Bitcoin::SIGHASH_TYPE[:all],
                                     sig_version: :witness_v0)

      signature = key.sign(sighash) + [Bitcoin::SIGHASH_TYPE[:all]].pack("C")

      tx.inputs[index].script_witness.stack << signature
      tx.inputs[index].script_witness.stack << key.pubkey
    end
  end

  def self.log_inputs(tx)
    log("Final inputs list:")
    tx.inputs.each_with_index do |input, index|
      log("Input #{index + 1}: #{input.out_point.txid} - #{input.out_point.index}")
    end
  end

  def self.broadcast(tx)
    tx_hex = tx.to_hex
    response = Faraday.post("#{ENV['MEMPOOL_API_URL']}/tx", tx_hex)
    log("Mempool response: #{response.body}")
    log("Transaction broadcast sent!")
  end

  def self.log(message)
    puts(message)
  end

  private_class_method :ask_recipient_address,
                       :ask_amount_btc,
                       :btc_to_sats,
                       :total_balance,
                       :calculate_fee,
                       :build_transaction,
                       :add_change_output,
                       :sign_transaction,
                       :log_inputs,
                       :sufficient_funds?,
                       :log
end
