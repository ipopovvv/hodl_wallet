# frozen_string_literal: true

RSpec.describe BalanceChecker do
  describe BalanceChecker::Checker do
    let(:client) { instance_double('Client') } # rubocop:disable RSpec/VerifiedDoubleReference
    let(:checker) { described_class.new(client) }
    let(:address) { 'bc1paddressxyz' }

    before do
      wallet_loader = instance_double(Wallet::Loader, key: double(to_p2tr: address)) # rubocop:disable RSpec/VerifiedDoubles
      allow(Wallet::Loader).to receive(:new).and_return(wallet_loader)
      allow(checker).to receive(:log_info)
    end

    context 'when there are no UTXOs' do
      before do
        allow(checker).to receive(:fetch_utxos).with(address, client).and_return([])
      end

      it 'logs zero balance' do
        checker.balance
        expect(checker).to have_received(:log_info).with('Balance: 0 sBTC')
      end
    end

    context 'when there are UTXOs' do
      let(:utxos) do
        [
          { 'value' => 50_000 },
          { 'value' => 150_000 }
        ]
      end

      before do
        allow(checker).to receive(:fetch_utxos).with(address, client).and_return(utxos)
      end

      it 'logs the calculated balance in sBTC' do
        checker.balance
        expect(checker).to have_received(:log_info).with('Balance: 0.002 sBTC')
      end
    end
  end
end
