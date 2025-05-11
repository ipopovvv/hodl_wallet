# frozen_string_literal: true

RSpec.describe Services::HttpClient do
  let(:base_url) { 'https://test.com' }

  before do
    described_class.configure do |config|
      config.base_url = base_url
      config.timeout = 5
      config.headers = { 'Content-Type' => 'application/json' }
    end
  end

  describe '#initialize' do
    let(:client) { described_class.new.client }

    it 'builds a Faraday client successfully' do
      expect(client).to be_a(Faraday::Connection)
    end

    it 'uses correct headers type' do
      expect(client.headers['Content-Type']).to eq('application/json')
    end

    it 'uses correct prefix' do
      expect(client.url_prefix.to_s).to eq("#{base_url}/")
    end
  end

  context 'when Faraday raises a connection error' do
    before do
      allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed.new('fail'))
    end

    it 'raises a ConnectionError with log' do
      expect { described_class.new }.to raise_error(Services::HttpClient::ConnectionError)
    end
  end

  context 'when Faraday raises a timeout error' do
    before do
      allow(Faraday).to receive(:new).and_raise(Faraday::TimeoutError.new('timeout'))
    end

    it 'raises a TimeoutError with log' do
      expect { described_class.new }.to raise_error(Services::HttpClient::TimeoutError)
    end
  end

  context 'when Faraday raises a parsing error' do
    before do
      allow(Faraday).to receive(:new).and_raise(Faraday::ParsingError.new('bad json'))
    end

    it 'raises a ParsingError with log' do
      expect { described_class.new }.to raise_error(Services::HttpClient::ParsingError)
    end
  end

  context 'when Faraday raises an unknown error' do
    before do
      allow(Faraday).to receive(:new).and_raise(StandardError.new('something broke'))
    end

    it 'raises a generic ConnectionError with log' do
      expect { described_class.new }.to raise_error(Services::HttpClient::ConnectionError)
    end
  end
end
