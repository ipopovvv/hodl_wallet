# frozen_string_literal: true

require_relative 'script_logger'

# rubocop:disable Metrics/ModuleLength
# Main Module for prepare and send BTC Transaction
module TransactionSender
  extend ScriptLogger

  MINIMUM_FEE = 2
  DUST_THRESHOLD = 330

  class TransactionSenderError < StandardError; end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  # Sends BTC from local wallet to user-specified address with fee calculation and safety checks
  def self.send_btc
    Bitcoin.chain_params = :signet

    recipient_address = ask_recipient_address
    amount_sats = btc_to_sats(ask_amount_btc)
    key = Wallet.load

    sender_address, output_key_bytes = derive_p2tr_details(key)
    log_info("Sender P2TR Address: #{sender_address}")

    spendable_utxos = fetch_and_filter_utxos(sender_address, output_key_bytes)
    confirmed_utxos = spendable_utxos.select { |utxo| utxo.dig('status', 'confirmed') }

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
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  # Derives Taproot (P2TR) address and output key bytes from the given key
  def self.derive_p2tr_details(key)
    sender_address = key.to_p2tr
    output_key_hex = key.xonly_pubkey
    output_key_bytes = output_key_hex.htb
    raise TransactionSenderError, 'Failed to get valid 32-byte P2TR output key.' unless output_key_bytes&.bytesize == 32

    [sender_address, output_key_bytes]
  rescue NoMethodError => e
    raise TransactionSenderError, "Method missing for P2TR key derivation (#{e.message}). Check bitcoinrb version."
  end

  # Fetches UTXOs for address and filters only those matching the expected output key
  def self.fetch_and_filter_utxos(address, expected_output_key)
    utxos = fetch_utxos(address)
    return [] if utxos.empty?

    conn = Faraday.new(url: ENV['MEMPOOL_API_URL']) { |f| f.adapter Faraday.default_adapter }

    utxos.each_with_object([]) do |utxo, result|
      result << utxo if valid_output_key?(conn, utxo, expected_output_key)
    rescue Faraday::Error, JSON::ParserError => e
      log_error(" -> Warning: Error processing TX #{utxo['txid']}: #{e.message}. Skipping.")
    end
  end

  # Fetches all UTXOs for the given address using mempool API
  def self.fetch_utxos(address)
    url = "#{ENV['MEMPOOL_API_URL']}/address/#{address}/utxo"
    response = Faraday.get(url)
    JSON.parse(response.body)
  rescue Faraday::Error => e
    raise TransactionSenderError, "Network error fetching UTXOs: #{e.message}"
  rescue JSON::ParserError => e
    raise TransactionSenderError, "Error parsing UTXO JSON response: #{e.message}"
  end

  # Gets the current fastest fee rate from mempool API, with fallback to minimum fee
  def self.fetch_fee_rate
    url = "#{ENV['MEMPOOL_API_URL']}/v1/fees/recommended"
    response = Faraday.get(url)
    data = JSON.parse(response.body)
    rate = data['fastestFee'] || MINIMUM_FEE
    [rate, MINIMUM_FEE].max
  rescue Faraday::Error => e
    raise TransactionSenderError, "Network error fetching fee rate: #{e.message}"
  rescue JSON::ParserError => e
    raise TransactionSenderError, "Error parsing fee rate JSON response: #{e.message}"
  end

  # Estimates final transaction fee with and without change output to get accurate size-based fee
  def self.calculate_final_fee(utxos, sender_addr, recip_addr, amount, fee_rate)
    tx_no_change = build_transaction(utxos, sender_addr, recip_addr, amount, 0, include_change: false)
    base_fee = calculate_vsize_fee(tx_no_change, fee_rate, utxos.size)
    tx_with_change = build_transaction(utxos, sender_addr, recip_addr, amount, base_fee, include_change: true)
    calculate_vsize_fee(tx_with_change, fee_rate, utxos.size)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Naming/MethodParameterName
  # Calculates transaction fee by estimating virtual size (vsize) and multiplying by fee rate
  def self.calculate_vsize_fee(tx, rate, num_inputs)
    return 0 if tx.in.empty? || tx.out.empty? || rate <= 0

    temp_tx = tx.dup
    temp_tx.in.each_with_index do |inp, i|
      inp.script_witness.stack << ("\x00" * 64) if inp.script_witness.stack.empty? && i < num_inputs
    end
    vsize = temp_tx.vsize
    return 0 if vsize <= 0

    (vsize * rate).ceil
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Naming/MethodParameterName

  # rubocop:disable Metrics/ParameterLists
  # Builds raw Bitcoin transaction with optional change output
  def self.build_transaction(utxos, sender_addr, recip_addr, amount, fee, include_change: true)
    tx = Bitcoin::Tx.new
    tx.version = 2
    utxos.each { |u| tx.in << Bitcoin::TxIn.new(out_point: Bitcoin::OutPoint.from_txid(u['txid'], u['vout'])) }
    tx.out << Bitcoin::TxOut.new(value: amount, script_pubkey: Bitcoin::Script.parse_from_addr(recip_addr))
    add_change_output(tx, utxos, sender_addr, amount, fee) if include_change
    tx
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Naming/MethodParameterName
  def self.add_change_output(tx, utxos, sender_addr, amount, fee)
    change = total_balance(utxos) - amount - fee
    return unless change >= DUST_THRESHOLD

    tx.out << Bitcoin::TxOut.new(value: change, script_pubkey: Bitcoin::Script.parse_from_addr(sender_addr))
  end
  # rubocop:enable Naming/MethodParameterName

  # rubocop:disable Metrics, Naming
  # Signs a Bitcoin transaction using provided UTXOs and key, ensuring output key match and valid data
  def self.sign_transaction(tx, spendable_utxos, key, expected_output_key)
    raise TransactionSenderError, 'Input/UTXO count mismatch.' unless tx.in.size == spendable_utxos.size

    prevouts = spendable_utxos.map do |u|
      Bitcoin::TxOut.new(
        value: u['value'],
        script_pubkey: Bitcoin::Script.parse_from_payload(u['scriptpubkey_hex'].htb)
      )
    end

    spendable_utxos.each_with_index do |utxo, index|
      output_key_script = utxo['output_key_from_script']
      unless utxo['scriptpubkey_hex'] && utxo['value'] && output_key_script
        raise TransactionSenderError,
              "Missing data for UTXO index #{index}."
      end
      unless output_key_script == expected_output_key
        raise TransactionSenderError,
              "Output Key mismatch on input ##{index}!"
      end

      script_pubkey = Bitcoin::Script.parse_from_payload(utxo['scriptpubkey_hex'].htb)
      sighash = tx.sighash_for_input(
        index,
        script_pubkey,
        amount: utxo['value'],
        sig_version: :taproot,
        prevouts: prevouts, hash_type: Bitcoin::SIGHASH_TYPE[:default]
      )
      signature = key.sign(sighash, algo: :schnorr)

      tx.in[index].script_witness = Bitcoin::ScriptWitness.new
      tx.in[index].script_witness.stack << signature
    end
    tx
  rescue StandardError => e
    raise TransactionSenderError, "Error during signing process: #{e.message}"
  end
  # rubocop:enable Metrics, Naming

  # rubocop:disable Metrics, Naming
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
    error_details = ''
    begin
      error_details = " Details: #{JSON.parse(e.response[:body])}" if e.response&.dig(:body)
    rescue JSON::ParserError
      error_details = " Raw Response: #{e.response[:body]}" if e.response&.dig(:body)
    end
    raise TransactionSenderError, "Transaction broadcast failed! Status: #{e.response&.dig(:status)}.#{error_details}"
  end
  # rubocop:enable Metrics, Naming

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  # Checks if the output key in the UTXO matches the expected key by fetching the transaction details
  def self.valid_output_key?(conn, utxo, expected_key)
    txid, vout = utxo.values_at('txid', 'vout')
    response = conn.get("tx/#{txid}")
    output = JSON.parse(response.body)['vout'][vout]
    return false unless output

    script_hex = output['scriptpubkey']
    return false unless script_hex

    script = script_hex.htb
    return false unless script.start_with?("\x51\x20".b) && script.bytesize == 34

    output_key = script[2..]
    return false unless output_key == expected_key

    utxo['scriptpubkey_hex'] = script_hex
    utxo['output_key_from_script'] = output_key
    true
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def self.total_balance(utxos)
    utxos.sum { |u| u['value'] }
  end

  def self.sufficient_funds?(total, amount, fee)
    total >= amount + fee
  end

  def self.ask_recipient_address
    print 'Recipient Address (Signet): '
    gets.strip
  end

  def self.ask_amount_btc
    print 'Amount (sBTC): '
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
# rubocop:enable Metrics/ModuleLength
