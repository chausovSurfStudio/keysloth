# frozen_string_literal: true

RSpec.describe KeySloth::Crypto do
  let(:password) { 'test_password_12345' }
  let(:logger) { mock_logger }
  let(:crypto) { described_class.new(password, logger) }

  describe '#initialize' do
    it 'creates crypto instance with valid password' do
      expect { described_class.new(password, logger) }.not_to raise_error
    end

    it 'raises error with empty password' do
      expect { described_class.new('', logger) }.to raise_error(KeySloth::CryptoError, /пустым/)
    end

    it 'raises error with short password' do
      expect do
        described_class.new('short', logger)
      end.to raise_error(KeySloth::CryptoError, /минимум 8/)
    end

    it 'raises error with nil password' do
      expect { described_class.new(nil, logger) }.to raise_error(KeySloth::CryptoError, /пустым/)
    end
  end

  describe '#encrypt_file' do
    let(:content) { 'test file content' }

    it 'encrypts file content successfully' do
      encrypted = crypto.encrypt_file(content)

      expect(encrypted).to be_a(String)
      expect(encrypted).not_to eq(content)
      expect { Base64.strict_decode64(encrypted) }.not_to raise_error
    end

    it 'produces different encrypted content for same input' do
      encrypted1 = crypto.encrypt_file(content)
      encrypted2 = crypto.encrypt_file(content)

      expect(encrypted1).not_to eq(encrypted2)
    end

    it 'handles empty content' do
      encrypted = crypto.encrypt_file('')
      expect(encrypted).to be_a(String)

      # Пустой контент превращается в пробел для совместимости с OpenSSL
      decrypted = crypto.decrypt_file(encrypted)
      expect(decrypted).to eq(' ')
    end

    it 'handles large content' do
      large_content = 'x' * 10_000
      encrypted = crypto.encrypt_file(large_content)
      expect(encrypted).to be_a(String)
    end

    it 'logs encryption process' do
      expect(logger).to receive(:debug).with('Начинаем шифрование файла')
      expect(logger).to receive(:debug).with(/успешно зашифрован/)

      crypto.encrypt_file(content)
    end
  end

  describe '#decrypt_file' do
    let(:content) { 'test file content for decryption' }

    it 'decrypts previously encrypted content' do
      encrypted = crypto.encrypt_file(content)
      decrypted = crypto.decrypt_file(encrypted)

      expect(decrypted).to eq(content)
    end

    it 'raises error with invalid password' do
      encrypted = crypto.encrypt_file(content)
      wrong_crypto = described_class.new('wrong_password_123', logger)

      expect do
        wrong_crypto.decrypt_file(encrypted)
      end.to raise_error(KeySloth::CryptoError, /Неверный пароль/)
    end

    it 'raises error with corrupted data' do
      corrupted_data = Base64.strict_encode64('corrupted')

      expect { crypto.decrypt_file(corrupted_data) }.to raise_error(KeySloth::CryptoError)
    end

    it 'raises error with invalid base64' do
      expect { crypto.decrypt_file('not_base64!') }.to raise_error(KeySloth::CryptoError)
    end

    it 'logs decryption process' do
      encrypted = crypto.encrypt_file(content)

      expect(logger).to receive(:debug).with('Начинаем дешифрование файла')
      expect(logger).to receive(:debug).with(/успешно расшифрован/)

      crypto.decrypt_file(encrypted)
    end
  end

  describe '#verify_integrity' do
    let(:content) { 'test content for integrity check' }

    it 'returns true for valid encrypted content' do
      encrypted = crypto.encrypt_file(content)
      expect(crypto.verify_integrity(encrypted)).to be true
    end

    it 'returns false for corrupted data' do
      corrupted_data = Base64.strict_encode64('corrupted')
      expect(crypto.verify_integrity(corrupted_data)).to be false
    end

    it 'returns false for invalid base64' do
      expect(crypto.verify_integrity('not_base64!')).to be false
    end

    it 'returns false for empty string' do
      expect(crypto.verify_integrity('')).to be false
    end

    it 'returns false for nil content' do
      expect(crypto.verify_integrity(nil)).to be false
    end

    it 'validates structure components' do
      encrypted = crypto.encrypt_file(content)

      # Манипулируем зашифрованными данными для проверки валидации
      decoded = Base64.strict_decode64(encrypted)
      corrupted = decoded[0..50] # Обрезаем данные
      corrupted_base64 = Base64.strict_encode64(corrupted)

      expect(crypto.verify_integrity(corrupted_base64)).to be false
    end

    it 'logs verification process' do
      encrypted = crypto.encrypt_file(content)

      expect(logger).to receive(:debug).with('Проверяем целостность зашифрованного файла')
      expect(logger).to receive(:debug).with('Файл прошел проверку целостности')

      crypto.verify_integrity(encrypted)
    end
  end

  describe '#verify_integrity_detailed' do
    let(:content) { 'test content for detailed integrity check' }

    it 'returns detailed verification result for valid content' do
      encrypted = crypto.encrypt_file(content)
      result = crypto.verify_integrity_detailed(encrypted)

      expect(result).to be_a(Hash)
      expect(result[:valid]).to be true
      expect(result[:structure_valid]).to be true
      expect(result[:decryption_valid]).to be true
      expect(result[:error]).to be_nil
    end

    it 'returns detailed result for invalid content' do
      corrupted_data = Base64.strict_encode64('corrupted')
      result = crypto.verify_integrity_detailed(corrupted_data)

      expect(result[:valid]).to be false
      expect(result[:structure_valid]).to be false
      expect(result[:decryption_valid]).to be false
    end

    it 'detects wrong password in detailed check' do
      encrypted = crypto.encrypt_file(content)
      wrong_crypto = described_class.new('wrong_password_123', logger)

      result = wrong_crypto.verify_integrity_detailed(encrypted)

      expect(result[:valid]).to be false
      expect(result[:structure_valid]).to be true
      expect(result[:decryption_valid]).to be false
      expect(result[:error]).to be_nil # Ошибка не устанавливается для неправильного пароля
    end

    it 'logs detailed verification process' do
      encrypted = crypto.encrypt_file(content)

      expect(logger).to receive(:debug).with('Выполняем детальную проверку целостности')
      expect(logger).to receive(:debug).with(/Детальная проверка завершена/)

      crypto.verify_integrity_detailed(encrypted)
    end
  end

  describe 'full encryption/decryption cycle' do
    it 'handles various file types correctly' do
      test_files = {
        'certificate.cer' => "-----BEGIN CERTIFICATE-----\nMIIBkTCB+wI...\n-----END CERTIFICATE-----",
        'config.json' => '{"key": "value", "number": 123, "array": [1, 2, 3]}',
        'profile.mobileprovisioning' => '<?xml version="1.0" encoding="UTF-8"?>...',
        'binary.p12' => "\x30\x82\x05\x10\x02\x01\x03\x30".b # Бинарные данные
      }

      test_files.each do |filename, content|
        encrypted = crypto.encrypt_file(content)
        decrypted = crypto.decrypt_file(encrypted)

        expect(decrypted).to eq(content), "Mismatch for #{filename}"
      end
    end

    it 'maintains data integrity across multiple cycles' do
      original_content = 'important secret data'

      5.times do
        encrypted = crypto.encrypt_file(original_content)
        decrypted = crypto.decrypt_file(encrypted)
        expect(decrypted).to eq(original_content)
      end
    end
  end
end
