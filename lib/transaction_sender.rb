require 'dotenv/load'
require 'faraday'
require 'json'
require 'bitcoin'
require_relative 'wallet'

module TransactionSender
  MINIMUM_FEE = 2
  DUST_THRESHOLD = 294

  def self.send_btc
    Bitcoin.chain_params = :signet

    recipient_address = ask_recipient_address
    amount_btc = ask_amount_btc
    amount_sats = btc_to_sats(amount_btc)

    log("Loading key from PRIVATE_KEY_WIF in .env file...")
    key = Wallet.load
    unless key
      log("Error: Failed to load wallet key."); return
    end
    log("Key loaded successfully.")
    sender_address = key.to_p2wpkh
    log("Address derived from loaded key: #{sender_address}")

    # Вычисляем PKH для нашего ключа ОДИН РАЗ
    begin
      pkh_from_loaded_key = Digest::RMD160.digest(Digest::SHA256.digest(key.pubkey))
      log("PKH from loaded key: #{pkh_from_loaded_key.bth}")
    rescue => e
      log("Error calculating PKH from loaded key: #{e.message}"); return
    end

    # Получаем ВСЕ UTXO для адреса и добавляем scriptPubKey/PKH
    augmented_utxos = fetch_and_augment_utxos(sender_address)
    unless augmented_utxos
      log("Failed to fetch UTXO details for address #{sender_address}"); return
    end
    log("Fetched details for #{augmented_utxos.size} UTXO(s) associated with address #{sender_address}.")

    # --- ФИЛЬТРАЦИЯ UTXO ---
    spendable_utxos = augmented_utxos.select do |utxo|
      utxo['pkh_from_script'] && utxo['pkh_from_script'] == pkh_from_loaded_key
    end
    log("Found #{spendable_utxos.size} UTXO(s) truly spendable with the loaded key (PKH match).")

    if spendable_utxos.empty?
      log("No UTXOs found that can be spent with the key in .env (PKH: #{pkh_from_loaded_key.bth}).")
      log("The address #{sender_address} might only have UTXOs requiring a different key, or no spendable UTXOs.")
      return
    end
    # --- Конец фильтрации ---

    # Используем только подтвержденные из отфильтрованного списка
    confirmed_utxos = spendable_utxos.select { |utxo| utxo.dig("status", "confirmed") }
    if confirmed_utxos.empty?
      log("No confirmed UTXOs found among the spendable ones for address #{sender_address}. Waiting for confirmations.")
      return
    end
    log("Using #{confirmed_utxos.size} confirmed and spendable UTXOs.")

    total_sats = total_balance(confirmed_utxos)
    log("Total available confirmed & spendable balance: #{total_sats} sats")

    # --- Расчет комиссии (используем только confirmed_utxos) ---
    fee_rate = fetch_fee_rate
    unless fee_rate; log("Error: Could not fetch fee rate."); return; end

    tx_no_change = build_transaction(confirmed_utxos, sender_address, recipient_address, amount_sats, 0, false)
    base_fee = calculate_fee(tx_no_change, fee_rate, confirmed_utxos.size)

    if total_sats < amount_sats + base_fee
      log("Insufficient spendable funds even without change output. Required: #{amount_sats} + Fee: ~#{base_fee}. Available: #{total_sats}")
      return
    end

    tx_with_change = build_transaction(confirmed_utxos, sender_address, recipient_address, amount_sats, base_fee, true)
    final_fee = calculate_fee(tx_with_change, fee_rate, confirmed_utxos.size)
    log("Final calculated fee (with potential change): #{final_fee} sats")

    unless sufficient_funds?(total_sats, amount_sats, final_fee)
      log("Insufficient spendable funds after final fee calculation. Required: #{amount_sats} + Fee: #{final_fee}. Available: #{total_sats}")
      return
    end

    # --- Построение, подпись и отправка (используем только confirmed_utxos) ---
    final_tx = build_transaction(confirmed_utxos, sender_address, recipient_address, amount_sats, final_fee, true)

    log("Signing transaction using the loaded key...")
    # Передаем ТОЛЬКО те UTXO, которые прошли проверку PKH
    signed_tx = sign_transaction(final_tx, confirmed_utxos, key, pkh_from_loaded_key)
    unless signed_tx; log("Error during transaction signing."); return; end

    log_inputs(signed_tx)
    log("Broadcasting transaction...")
    broadcast(signed_tx)

  rescue Faraday::Error => e; log("Network Error: #{e&.message}")
  rescue Bitcoin::Errors => e; log("Error: Invalid Address Format - #{e&.message}")
  rescue StandardError => e; log("Unexpected Error: #{e&.message}\n#{e&.backtrace&.join("\n")}")
  end

  # --- Методы получения данных ---
  def self.ask_recipient_address; print "Recv Addr (Signet): "; gets.strip; end
  def self.ask_amount_btc; print "sBTC Amount: "; gets.strip.to_f; end
  def self.btc_to_sats(btc); (btc * 100_000_000).to_i; end

  def self.fetch_utxos(address)
    url = "#{ENV['MEMPOOL_API_URL']}/address/#{address}/utxo"
    log("Fetching base UTXOs from: #{url}")
    response = Faraday.get(url)
    if response.success?; JSON.parse(response.body)
    else log("Error fetching UTXOs: #{response.status}"); nil end
  rescue => e; log("Error during fetch_utxos: #{e.message}"); nil end

  def self.fetch_and_augment_utxos(address)
    base_utxos = fetch_utxos(address)
    return nil unless base_utxos
    return [] if base_utxos.empty?

    log("Fetching full TX details for #{base_utxos.size} UTXO(s)...")
    augmented_utxos = []
    conn = Faraday.new(url: ENV['MEMPOOL_API_URL']) { |f| f.adapter Faraday.default_adapter }

    base_utxos.each do |utxo|
      txid = utxo['txid']; vout_index = utxo['vout']
      begin
        response = conn.get("tx/#{txid}")
        if response.success?
          tx_data = JSON.parse(response.body)
          output_data = tx_data['vout'][vout_index]
          script_hex = output_data['scriptpubkey'] if output_data
          if script_hex
            utxo['scriptpubkey_hex'] = script_hex
            # Извлекаем PKH прямо здесь
            script_bytes = script_hex.htb
            if script_bytes.start_with?("\x00\x14".b) && script_bytes.bytesize == 22
              utxo['pkh_from_script'] = script_bytes[2..-1] # Бинарный PKH
              augmented_utxos << utxo
            else
              log(" -> UTXO #{txid}:#{vout_index} has non-P2WPKH script: #{script_hex}. Skipping.")
            end
          else
            log(" -> Could not find scriptPubKey for #{txid}:#{vout_index}. Skipping.")
          end
        else
          log(" -> Failed to fetch TX #{txid}: #{response.status}. Skipping.")
        end
      rescue => e
        log(" -> Error processing TX #{txid}: #{e.message}. Skipping.")
      end
    end
    augmented_utxos
  end

  def self.fetch_fee_rate
    url = "#{ENV['MEMPOOL_API_URL']}/v1/fees/recommended"
    log("Fetching fee rate from: #{url}")
    response = Faraday.get(url)
    if response.success?
      data = JSON.parse(response.body)
      rate = data["fastestFee"]
      log("Recommended fee rate: #{rate} sats/vbyte")
      [rate, MINIMUM_FEE].max # Используем максимум из рекомендованной и минимальной
    else log("Error fetching fee rate: #{response.status}"); nil end
  rescue => e; log("Error during fetch_fee_rate: #{e.message}"); nil end

  # --- Вспомогательные методы расчета ---
  def self.total_balance(utxos); utxos.sum { |u| u["value"] }; end
  def self.calculate_fee(tx, rate, num_inputs)
    return 0 if tx.in.empty? || tx.out.empty? || rate <= 0
    temp_tx = tx.dup
    temp_tx.in.each_with_index do |inp, i|
      if inp.script_witness.stack.empty? && i < num_inputs
        inp.script_witness.stack << ("\x00"*71) << ("\x00"*33)
      end
    end
    vsize = temp_tx.vsize; return 0 if vsize <= 0
    (vsize * rate).ceil
  end
  def self.sufficient_funds?(total, amount, fee); total >= amount + fee; end

  # --- Методы построения и подписи ---
  def self.build_transaction(utxos, sender_addr, recip_addr, amount, fee, include_change)
    tx = Bitcoin::Tx.new; tx.version = 2
    utxos.each { |u| tx.in << Bitcoin::TxIn.new(out_point: Bitcoin::OutPoint.from_txid(u["txid"], u["vout"])) }
    tx.out << Bitcoin::TxOut.new(value: amount, script_pubkey: Bitcoin::Script.parse_from_addr(recip_addr))
    add_change_output(tx, utxos, sender_addr, amount, fee) if include_change
    tx
  end

  def self.add_change_output(tx, utxos, sender_addr, amount, fee)
    change = total_balance(utxos) - amount - fee
    if change >= DUST_THRESHOLD
      log("Adding change output: #{change} sats to #{sender_addr}")
      tx.out << Bitcoin::TxOut.new(value: change, script_pubkey: Bitcoin::Script.parse_from_addr(sender_addr))
    else
      log("Change (#{change} sats) below dust threshold or zero. No change output.")
    end
  end

  # Принимает pkh_from_loaded_key, чтобы не вычислять его снова
  def self.sign_transaction(tx, spendable_utxos, key, pkh_from_loaded_key)
    unless tx.in.size == spendable_utxos.size
      log("Error: Input/UTXO count mismatch during signing."); return nil
    end
    log("Signing #{spendable_utxos.size} input(s)...")
    public_key_bytes = key.pubkey # Получаем бинарный ключ

    spendable_utxos.each_with_index do |utxo, index|
      script_hex = utxo['scriptpubkey_hex']
      amount = utxo["value"]
      pkh_from_script = utxo['pkh_from_script'] # Уже извлечен ранее

      unless script_hex && amount && pkh_from_script
        log("Error: Missing data for UTXO at index #{index}."); return nil
      end

      # Дополнительная проверка (хотя мы уже отфильтровали)
      unless pkh_from_script == pkh_from_loaded_key
        log("!!! Error: PKH mismatch detected during signing for input ##{index} - this should not happen after filtering!"); return nil
      end

      begin
        script_pubkey = Bitcoin::Script.parse_from_payload(script_hex.htb)
        sighash = tx.sighash_for_input(index, script_pubkey, amount: amount, sig_version: :witness_v0)
        signature = key.sign(sighash) + [Bitcoin::SIGHASH_TYPE[:all]].pack('C')

        tx.in[index].script_witness = Bitcoin::ScriptWitness.new
        tx.in[index].script_witness.stack << signature
        tx.in[index].script_witness.stack << public_key_bytes # Добавляем бинарный ключ

      rescue => e
        log("Error signing input ##{index}: #{e.message}\n#{e.backtrace&.join("\n")}"); return nil
      end
    end
    log("All spendable inputs signed successfully.")
    tx # Возвращаем подписанную транзакцию
  end

  def self.log_inputs(tx)
    log("Final inputs in transaction:")
    tx.in.each_with_index do |input, i|
      log("Input #{i}: #{input.out_point.txid}:#{input.out_point.index}, Witness Items: #{input.script_witness.stack.size}")
    end
  end

  def self.broadcast(tx)
    tx_hex = tx.to_hex; log("Tx Hex: #{tx_hex}")
    url = "#{ENV['MEMPOOL_API_URL']}/tx"; log("Broadcasting to: #{url}")
    conn = Faraday.new { |f| f.adapter Faraday.default_adapter }
    resp = conn.post(url) { |req| req.headers['Content-Type'] = 'text/plain'; req.body = tx_hex }
    log("Broadcast Resp Status: #{resp.status}"); log("Broadcast Resp Body: #{resp.body}")
    if resp.success?
      log("Tx broadcast successful! TXID: #{resp.body}")
    else
      log("Tx broadcast failed!")
      begin; log("Error details: #{JSON.parse(resp.body)}")
      rescue; log("Raw error response: #{resp.body}"); end
    end
  end

  def self.log(msg); puts msg; end
  private_class_method :ask_recipient_address, :ask_amount_btc, :btc_to_sats, :log
end