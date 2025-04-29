require 'bitcoin'

module Wallet
  KEYS_DIR = 'keys'
  PRIVATE_KEY_FILE = "#{KEYS_DIR}/private_key"

  def self.generate
    Bitcoin.chain_params = :signet

    key = Bitcoin::Key.generate
    Dir.mkdir(KEYS_DIR) unless Dir.exist?(KEYS_DIR)

    File.write(PRIVATE_KEY_FILE, key.to_wif)

    address = key.to_p2wpkh
    puts "✅ Wallet generated!"
    puts "Address: #{address}"

    address
  end

  def self.load
    Bitcoin.chain_params = :signet

    unless File.exist?(PRIVATE_KEY_FILE)
      puts "Private key not found. Generate a wallet."
      exit
    end

    wif = File.read(PRIVATE_KEY_FILE).strip
    Bitcoin::Key.from_wif(wif)
  end
end
