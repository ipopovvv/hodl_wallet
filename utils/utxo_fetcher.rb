# frozen_string_literal: true

require_relative 'script_logger'

# module UtxoFetcher
module UtxoFetcher
  def fetch_utxos(address, client)
    log_info("Fetching utxos for #{address}...")
    client.get("/signet/api/address/#{address}/utxo").body
  end
end
