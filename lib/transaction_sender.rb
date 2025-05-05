# frozen_string_literal: true

require_relative '../utils/script_logger'
require_relative '../utils/utxo_fetcher'

# Main Module for prepare and send BTC Transaction
module TransactionSender
  MINIMUM_FEE_RATE = 2
  DUST_THRESHOLD = 330

  class TransactionSenderError < StandardError; end

  # rubocop:disable Metrics/ClassLength
  # Main class for prepare and send BTC Transaction
  class Sender
    include ScriptLogger
    include UtxoFetcher

    def initialize(client)
      @client = client
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # Sends BTC from local wallet to user-specified address with fee calculation and safety checks
    def send_btc
      Bitcoin.chain_params = :signet

      recipient_address = ask_recipient_address
      amount_sats = btc_to_sats(ask_amount_btc)
      key = Wallet::Loader.new.key
      sender_address, output_key_bytes = derive_p2tr_details(key)
      log_info("Sender P2TR Address: #{sender_address}")
      confirmed_utxos = load_confirmed_spendable_utxos(sender_address, output_key_bytes)
      return unless confirmed_utxos

      total_sats = log_total_balance(confirmed_utxos)
      fee_rate = fetch_fee_rate
      final_fee = estimate_final_fee(confirmed_utxos, sender_address, recipient_address, amount_sats, fee_rate)
      return unless sufficient_funds?(total_sats, amount_sats, final_fee)

      tx = build_transaction(confirmed_utxos, sender_address, recipient_address, amount_sats, final_fee)
      signed_tx = sign_transaction(tx, confirmed_utxos, key, output_key_bytes)
      broadcast(signed_tx)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    # Fetch and filter UTXOs for the given sender, then return only confirmed ones
    def load_confirmed_spendable_utxos(sender_address, output_key_bytes)
      utxos = fetch_and_filter_utxos(sender_address, output_key_bytes)
      confirmed = utxos.select { |utxo| utxo.dig('status', 'confirmed') }

      if confirmed.empty?
        log_info("No confirmed spendable UTXOs found for address #{sender_address}.")
        return nil
      end

      log_info("Using #{confirmed.size} confirmed and spendable UTXO(s).")
      confirmed
    end

    # Log and return the total balance from confirmed UTXOs
    def log_total_balance(utxos)
      total = total_balance(utxos)
      log_info("Total spendable balance: #{total} sats")
      total
    end

    # Estimate final transaction fee and log it
    def estimate_final_fee(utxos, sender, recipient, amount, fee_rate)
      fee = calculate_final_fee(utxos, sender, recipient, amount, fee_rate)
      log_info("Estimated final fee: #{fee} sats")
      fee
    end

    # Check if the wallet has enough funds, and log message if not
    def sufficient_funds?(total, amount, fee)
      if total < amount + fee
        log_info("Insufficient funds. Required: #{amount} + Fee: #{fee}. Available: #{total}")
        return false
      end
      true
    end

    # Derives Taproot (P2TR) address and output key bytes from the given key
    def derive_p2tr_details(key)
      sender_address = key.to_p2tr
      output_key_hex = key.xonly_pubkey
      output_key_bytes = output_key_hex.htb
      unless output_key_bytes&.bytesize == 32
        raise TransactionSenderError, 'Failed to get valid 32-byte P2TR output key.'
      end

      [sender_address, output_key_bytes]
    end

    # Fetches UTXOs for address and filters only those matching the expected output key
    def fetch_and_filter_utxos(address, expected_output_key)
      utxos = fetch_utxos(address, @client)
      return [] if utxos.empty?

      utxos.each_with_object([]) do |utxo, result|
        result << utxo if valid_output_key?(utxo, expected_output_key)
      end
    end

    # Gets the current fastest fee rate from mempool API, with fallback to minimum fee
    def fetch_fee_rate
      response = @client.get('/signet/api/v1/fees/recommended')
      rate = response.body['fastestFee'] || MINIMUM_FEE_RATE
      [rate, MINIMUM_FEE_RATE].max
    end

    # Estimates final transaction fee with and without change output to get accurate size-based fee
    def calculate_final_fee(utxos, sender_addr, recip_addr, amount, fee_rate)
      tx_no_change = build_transaction(utxos, sender_addr, recip_addr, amount, 0, include_change: false)
      base_fee = calculate_vsize_fee(tx_no_change, fee_rate, utxos.size)
      tx_with_change = build_transaction(utxos, sender_addr, recip_addr, amount, base_fee, include_change: true)
      calculate_vsize_fee(tx_with_change, fee_rate, utxos.size)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Naming/MethodParameterName
    # Calculates transaction fee by estimating virtual size (vsize) and multiplying by fee rate
    def calculate_vsize_fee(tx, rate, num_inputs)
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
    def build_transaction(utxos, sender_addr, recip_addr, amount, fee, include_change: true)
      tx = Bitcoin::Tx.new
      tx.version = 2
      utxos.each { |u| tx.in << Bitcoin::TxIn.new(out_point: Bitcoin::OutPoint.from_txid(u['txid'], u['vout'])) }
      tx.out << Bitcoin::TxOut.new(value: amount, script_pubkey: Bitcoin::Script.parse_from_addr(recip_addr))
      add_change_output(tx, utxos, sender_addr, amount, fee) if include_change
      tx
    end
    # rubocop:enable Metrics/ParameterLists

    # rubocop:disable Naming/MethodParameterName
    def add_change_output(tx, utxos, sender_addr, amount, fee)
      change = total_balance(utxos) - amount - fee
      return unless change >= DUST_THRESHOLD

      tx.out << Bitcoin::TxOut.new(value: change, script_pubkey: Bitcoin::Script.parse_from_addr(sender_addr))
    end
    # rubocop:enable Naming/MethodParameterName

    # rubocop:disable Naming
    # Signs a Bitcoin transaction using provided UTXOs and key, ensuring output key match and valid data
    def sign_transaction(tx, spendable_utxos, key, expected_output_key)
      raise TransactionSenderError, 'Input/UTXO count mismatch.' unless tx.in.size == spendable_utxos.size

      prevouts = prepare_prevouts(spendable_utxos)
      spendable_utxos.each_with_index do |utxo, index|
        validate_utxo_data(utxo, index, expected_output_key)
        script_pubkey = Bitcoin::Script.parse_from_payload(utxo['scriptpubkey_hex'].htb)
        sighash = generate_sighash(tx, index, script_pubkey, utxo, prevouts)
        signature = key.sign(sighash, algo: :schnorr)
        add_signature_to_input(tx, index, signature)
      end
      tx
    end
    # rubocop:enable Naming

    # Prepare the prevouts (previous outputs) for the sighash computation
    def prepare_prevouts(spendable_utxos)
      spendable_utxos.map do |u|
        Bitcoin::TxOut.new(
          value: u['value'],
          script_pubkey: Bitcoin::Script.parse_from_payload(u['scriptpubkey_hex'].htb)
        )
      end
    end

    # Validate UTXO data and ensure consistency with expected output key
    def validate_utxo_data(utxo, index, expected_output_key)
      raise TransactionSenderError, "Missing data for UTXO index #{index}." unless valid_utxo?(utxo)

      output_key_script = utxo['output_key_from_script']
      return if output_key_script == expected_output_key

      raise TransactionSenderError, "Output Key mismatch on input ##{index}!"
    end

    # Check if the UTXO contains all required data
    def valid_utxo?(utxo)
      utxo['scriptpubkey_hex'] && utxo['value'] && utxo['output_key_from_script']
    end

    # rubocop:disable Naming/MethodParameterName
    # Generate the sighash for the current UTXO index
    def generate_sighash(tx, index, script_pubkey, utxo, prevouts)
      tx.sighash_for_input(
        index,
        script_pubkey,
        amount: utxo['value'],
        sig_version: :taproot,
        prevouts: prevouts,
        hash_type: Bitcoin::SIGHASH_TYPE[:default]
      )
    end
    # rubocop:enable Naming/MethodParameterName

    # rubocop:disable Naming/MethodParameterName
    # Add the generated signature to the transaction input
    def add_signature_to_input(tx, index, signature)
      tx.in[index].script_witness = Bitcoin::ScriptWitness.new
      tx.in[index].script_witness.stack << signature
    end
    # rubocop:enable Naming/MethodParameterName

    # rubocop:disable Naming
    def broadcast(tx)
      log_info('Broadcasting transaction...')
      response = @client.post('/signet/api/tx') do |req|
        req.headers['Content-Type'] = 'text/plain'
        req.body = tx.to_hex
      end

      log_info("Transaction broadcast successful! TXID: #{response.body}")
    end
    # rubocop:enable Naming

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # Checks if the output key in the UTXO matches the expected key by fetching the transaction details
    def valid_output_key?(utxo, expected_key)
      txid, vout = utxo.values_at('txid', 'vout')
      response = @client.get("/signet/api/tx/#{txid}")
      output = response.body['vout'][vout]
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

    def total_balance(utxos)
      utxos.sum { |u| u['value'] }
    end

    def ask_recipient_address
      print 'Recipient Address (Signet): '
      gets&.strip
    end

    def ask_amount_btc
      print 'Amount (sBTC): '
      gets&.strip.to_f
    end

    def btc_to_sats(btc)
      (btc * 100_000_000).to_i
    end
  end
  # rubocop:enable Metrics/ClassLength
end
