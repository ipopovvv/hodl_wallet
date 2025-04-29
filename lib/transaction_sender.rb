require_relative 'script_logger'

module TransactionSender
  extend ScriptLogger

  MINIMUM_FEE = 2
  DUST_THRESHOLD = 330

  class TransactionSenderError < StandardError; end

  def self.send_btc
    Bitcoin.chain_params = :signet

    recipient_address = ask_recipient_address
    amount_sats = btc_to_sats(ask_amount_btc)
    key = Wallet.load

    sender_address, output_key_bytes = derive_p2tr_details(key)
    log_info("Sender P2TR Address: #{sender_address}")

    spendable_utxos = fetch_and_filter_utxos(sender_address, output_key_bytes)
    confirmed_utxos = spendable_utxos.select { |utxo| utxo.dig("status", "confirmed") }

    if confirmed_utxos.empty?
      log_info("No confirmed spendable UTXOs found for address #{sender_address}.")
      return
    end
    log_info("Using #{confirmed_utxos.size} confirmed and spendable UTXO(s).")

    total_sats = total_balance(confirmed_utxos)
    log_info("Total spendable balance: #{total_sats} sats")

    fee_rate = fetch_fee_rate
    final_fee = calculate_final_fee(confirmed_utxos, sender_address, recipient_address, amount_sats, fee_rate)
    log_info("Estimated final fee: #{final_fee} sats")

    unless sufficient_funds?(total_sats, amount_sats, final_fee)
      log_info("Insufficient funds. Required: #{amount_sats} + Fee: #{final_fee}. Available: #{total_sats}")
      return
    end

    final_tx = build_transaction(confirmed_utxos, sender_address, recipient_address, amount_sats, final_fee)
    signed_tx = sign_transaction(final_tx, confirmed_utxos, key, output_key_bytes)
    broadcast(signed_tx)

  rescue Bitcoin::Errors => e
    log_error("Error: Invalid Bitcoin address format - #{e.message}")
  rescue TransactionSenderError, Faraday::Error, JSON::ParserError => e
    log_error("Error: #{e.message}")
  rescue StandardError => e
    log_error("Unexpected Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
  end

  def self.derive_p2tr_details(key)
    sender_address = key.to_p2tr
    output_key_hex = key.xonly_pubkey
    output_key_bytes = output_key_hex.htb
    raise TransactionSenderError, "Failed to get valid 32-byte P2TR output key." unless output_key_bytes&.bytesize == 32
    return sender_address, output_key_bytes
  rescue NoMethodError => e
    raise TransactionSenderError, "Method missing for P2TR key derivation (#{e.message}). Check bitcoinrb version."
  end

  def self.fetch_and_filter_utxos(address, expected_output_key)
    base_utxos = fetch_utxos(address)
    return [] if base_utxos.empty?

    spendable_utxos = []
    conn = Faraday.new(url: ENV['MEMPOOL_API_URL']) { |f| f.adapter Faraday.default_adapter }

    base_utxos.each do |utxo|
      txid = utxo['txid']; vout_index = utxo['vout']
      begin
        response = conn.get("tx/#{txid}")
        tx_data = JSON.parse(response.body)
        output_data = tx_data['vout'][vout_index]
        script_hex = output_data['scriptpubkey'] if output_data
        if script_hex
          script_bytes = script_hex.htb
          if script_bytes.start_with?("\x51\x20".b) && script_bytes.bytesize == 34
            output_key_script = script_bytes[2..-1]
            if output_key_script == expected_output_key
              utxo['scriptpubkey_hex'] = script_hex
              utxo['output_key_from_script'] = output_key_script
              spendable_utxos << utxo
            end
          end
        end
      rescue Faraday::Error, JSON::ParserError => e
        log_error(" -> Warning: Error processing TX #{txid}: #{e.message}. Skipping.")
      end
    end
    spendable_utxos
  end

  def self.fetch_utxos(address)
    url = "#{ENV['MEMPOOL_API_URL']}/address/#{address}/utxo"
    response = Faraday.get(url)
    JSON.parse(response.body)
  rescue Faraday::Error => e
    raise TransactionSenderError, "Network error fetching UTXOs: #{e.message}"
  rescue JSON::ParserError => e
    raise TransactionSenderError, "Error parsing UTXO JSON response: #{e.message}"
  end

  def self.fetch_fee_rate
    url = "#{ENV['MEMPOOL_API_URL']}/v1/fees/recommended"
    response = Faraday.get(url)
    data = JSON.parse(response.body)
    rate = data["fastestFee"] || MINIMUM_FEE
    [rate, MINIMUM_FEE].max
  rescue Faraday::Error => e
    raise TransactionSenderError, "Network error fetching fee rate: #{e.message}"
  rescue JSON::ParserError => e
    raise TransactionSenderError, "Error parsing fee rate JSON response: #{e.message}"
  end

  def self.calculate_final_fee(utxos, sender_addr, recip_addr, amount, fee_rate)
    tx_no_change = build_transaction(utxos, sender_addr, recip_addr, amount, 0, false)
    base_fee = calculate_vsize_fee(tx_no_change, fee_rate, utxos.size)
    tx_with_change = build_transaction(utxos, sender_addr, recip_addr, amount, base_fee, true)
    final_fee = calculate_vsize_fee(tx_with_change, fee_rate, utxos.size)
    final_fee
  end

  def self.calculate_vsize_fee(tx, rate, num_inputs)
    return 0 if tx.in.empty? || tx.out.empty? || rate <= 0
    temp_tx = tx.dup
    temp_tx.in.each_with_index do |inp, i|
      if inp.script_witness.stack.empty? && i < num_inputs
        inp.script_witness.stack << ("\x00" * 64)
      end
    end
    vsize = temp_tx.vsize
    return 0 if vsize <= 0
    (vsize * rate).ceil
  end

  def self.build_transaction(utxos, sender_addr, recip_addr, amount, fee, include_change = true)
    tx = Bitcoin::Tx.new
    tx.version = 2
    utxos.each { |u| tx.in << Bitcoin::TxIn.new(out_point: Bitcoin::OutPoint.from_txid(u["txid"], u["vout"])) }
    tx.out << Bitcoin::TxOut.new(value: amount, script_pubkey: Bitcoin::Script.parse_from_addr(recip_addr))
    add_change_output(tx, utxos, sender_addr, amount, fee) if include_change
    tx
  end

  def self.add_change_output(tx, utxos, sender_addr, amount, fee)
    change = total_balance(utxos) - amount - fee
    if change >= DUST_THRESHOLD
      tx.out << Bitcoin::TxOut.new(value: change, script_pubkey: Bitcoin::Script.parse_from_addr(sender_addr))
    end
  end

  def self.sign_transaction(tx, spendable_utxos, key, expected_output_key)
    raise TransactionSenderError, "Input/UTXO count mismatch." unless tx.in.size == spendable_utxos.size

    prevouts = spendable_utxos.map do |u|
      Bitcoin::TxOut.new(value: u['value'], script_pubkey: Bitcoin::Script.parse_from_payload(u['scriptpubkey_hex'].htb))
    end

    spendable_utxos.each_with_index do |utxo, index|
      output_key_script = utxo['output_key_from_script']
      raise TransactionSenderError, "Missing data for UTXO index #{index}." unless utxo['scriptpubkey_hex'] && utxo['value'] && output_key_script
      raise TransactionSenderError, "Output Key mismatch on input ##{index}!" unless output_key_script == expected_output_key

      script_pubkey = Bitcoin::Script.parse_from_payload(utxo['scriptpubkey_hex'].htb)
      sighash = tx.sighash_for_input(index, script_pubkey, amount: utxo['value'], sig_version: :taproot, prevouts: prevouts, hash_type: Bitcoin::SIGHASH_TYPE[:default])
      signature = key.sign(sighash, algo: :schnorr)

      tx.in[index].script_witness = Bitcoin::ScriptWitness.new
      tx.in[index].script_witness.stack << signature
    end
    tx
  rescue => e
    raise TransactionSenderError, "Error during signing process: #{e.message}"
  end

  def self.broadcast(tx)
    tx_hex = tx.to_hex
    url = "#{ENV['MEMPOOL_API_URL']}/tx"
    log_info("Broadcasting to: #{url}")
    conn = Faraday.new { |f| f.adapter Faraday.default_adapter }
    response = conn.post(url) do |req|
      req.headers['Content-Type'] = 'text/plain'
      req.body = tx_hex
    end

    log_info("Broadcast Response Status: #{response.status}")

    log_info("Transaction broadcast successful! TXID: #{response.body}")
  rescue Faraday::Error => e
    error_details = ""
    begin
      error_details = " Details: #{JSON.parse(e.response[:body])}" if e.response&.dig(:body)
    rescue JSON::ParserError
      error_details = " Raw Response: #{e.response[:body]}" if e.response&.dig(:body)
    end
    raise TransactionSenderError, "Transaction broadcast failed! Status: #{e.response&.dig(:status)}.#{error_details}"
  end

  def self.total_balance(utxos)
    utxos.sum { |u| u["value"] }
  end

  def self.sufficient_funds?(total, amount, fee)
    total >= amount + fee
  end

  def self.ask_recipient_address
    print "Recipient Address (Signet): "
    gets.strip
  end

  def self.ask_amount_btc
    print "Amount (sBTC): "
    gets.strip.to_f
  end

  def self.btc_to_sats(btc)
    (btc * 100_000_000).to_i
  end

  private_class_method :derive_p2tr_details,
                       :fetch_and_filter_utxos,
                       :fetch_utxos,
                       :fetch_fee_rate,
                       :calculate_final_fee,
                       :calculate_vsize_fee,
                       :build_transaction,
                       :add_change_output,
                       :sign_transaction,
                       :broadcast,
                       :total_balance,
                       :sufficient_funds?,
                       :ask_recipient_address,
                       :ask_amount_btc,
                       :btc_to_sats

end
