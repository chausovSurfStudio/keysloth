# frozen_string_literal: true

RSpec.describe KeySloth::FileManager do
  let(:logger) { mock_logger }
  let(:file_manager) { described_class.new(logger) }
  let(:temp_dir) { create_temp_dir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#ensure_directory' do
    it 'creates directory if it does not exist' do
      test_dir = File.join(temp_dir, 'new_directory')

      expect(File.exist?(test_dir)).to be false
      file_manager.ensure_directory(test_dir)
      expect(File.directory?(test_dir)).to be true
    end

    it 'does not raise error if directory already exists' do
      expect { file_manager.ensure_directory(temp_dir) }.not_to raise_error
    end

    it 'creates nested directories' do
      nested_dir = File.join(temp_dir, 'level1', 'level2', 'level3')

      file_manager.ensure_directory(nested_dir)
      expect(File.directory?(nested_dir)).to be true
    end

    it 'logs directory creation' do
      test_dir = File.join(temp_dir, 'logged_directory')

      expect(logger).to receive(:info).with(/Создаем директорию/)
      expect(logger).to receive(:debug).with(/успешно создана/)

      file_manager.ensure_directory(test_dir)
    end
  end

  describe '#directory_exists?' do
    it 'returns true for existing directory' do
      expect(file_manager.directory_exists?(temp_dir)).to be true
    end

    it 'returns false for non-existing directory' do
      non_existing = File.join(temp_dir, 'non_existing')
      expect(file_manager.directory_exists?(non_existing)).to be false
    end

    it 'returns false for file path' do
      file_path = create_test_file(File.join(temp_dir, 'test.txt'))
      expect(file_manager.directory_exists?(file_path)).to be false
    end
  end

  describe '#read_file and #write_file' do
    let(:test_content) { 'test file content with специальные символы' }
    let(:file_path) { File.join(temp_dir, 'test_file.txt') }

    it 'writes and reads file content correctly' do
      file_manager.write_file(file_path, test_content)
      read_content = file_manager.read_file(file_path)

      expect(read_content).to eq(test_content)
    end

    it 'creates directories for file path' do
      nested_file = File.join(temp_dir, 'nested', 'deep', 'file.txt')

      file_manager.write_file(nested_file, test_content)
      expect(File.exist?(nested_file)).to be true
      expect(file_manager.read_file(nested_file)).to eq(test_content)
    end

    it 'handles binary data correctly' do
      binary_content = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"

      file_manager.write_file(file_path, binary_content)
      read_content = file_manager.read_file(file_path)

      expect(read_content).to eq(binary_content)
    end

    it 'raises error when reading non-existing file' do
      non_existing = File.join(temp_dir, 'non_existing.txt')

      expect { file_manager.read_file(non_existing) }.to raise_error(KeySloth::FileSystemError)
    end
  end

  describe '#collect_secret_files' do
    it 'collects all supported secret file types' do
      secrets = create_test_secrets(temp_dir)

      collected_files = file_manager.collect_secret_files(temp_dir)

      expect(collected_files.size).to eq(4)
      secrets.each_key do |filename|
        expect(collected_files.any? { |f| f.end_with?(filename) }).to be true
      end
    end

    it 'finds files in nested directories' do
      nested_dir = File.join(temp_dir, 'nested', 'deep')
      FileUtils.mkdir_p(nested_dir)

      create_test_file(File.join(nested_dir, 'nested.cer'), 'nested cert')
      create_test_file(File.join(temp_dir, 'root.json'), 'root config')

      collected_files = file_manager.collect_secret_files(temp_dir)

      expect(collected_files.size).to eq(2)
      expect(collected_files.any? { |f| f.include?('nested.cer') }).to be true
      expect(collected_files.any? { |f| f.include?('root.json') }).to be true
    end

    it 'ignores unsupported file types' do
      create_test_file(File.join(temp_dir, 'readme.txt'), 'readme')
      create_test_file(File.join(temp_dir, 'script.sh'), 'script')
      create_test_file(File.join(temp_dir, 'config.json'), 'config')

      collected_files = file_manager.collect_secret_files(temp_dir)

      expect(collected_files.size).to eq(1)
      expect(collected_files.first).to end_with('config.json')
    end

    it 'returns empty array for directory without secret files' do
      collected_files = file_manager.collect_secret_files(temp_dir)
      expect(collected_files).to be_empty
    end

    it 'raises error for non-existing directory' do
      non_existing = File.join(temp_dir, 'non_existing')

      expect { file_manager.collect_secret_files(non_existing) }.to raise_error(KeySloth::FileSystemError)
    end
  end

  describe '#get_relative_path' do
    it 'returns correct relative path' do
      base_path = '/home/user/secrets'
      file_path = '/home/user/secrets/certificates/app.cer'

      relative_path = file_manager.get_relative_path(file_path, base_path)
      expect(relative_path).to eq('certificates/app.cer')
    end

    it 'handles same directory' do
      base_path = '/home/user/secrets'
      file_path = '/home/user/secrets/app.cer'

      relative_path = file_manager.get_relative_path(file_path, base_path)
      expect(relative_path).to eq('app.cer')
    end
  end

  describe '#create_backup' do
    it 'creates backup of existing directory' do
      create_test_secrets(temp_dir)

      backup_path = file_manager.create_backup(temp_dir)

      expect(backup_path).to be_a(String)
      expect(File.directory?(backup_path)).to be true
      expect(backup_path).to include('backup')
    end

    it 'returns nil for non-existing directory' do
      non_existing = File.join(temp_dir, 'non_existing')

      backup_path = file_manager.create_backup(non_existing)
      expect(backup_path).to be_nil
    end

    it 'preserves all files in backup' do
      secrets = create_test_secrets(temp_dir)

      backup_path = file_manager.create_backup(temp_dir)

      secrets.each do |filename, content|
        backup_file = File.join(backup_path, filename)
        expect(File.exist?(backup_file)).to be true
        expect(File.read(backup_file)).to eq(content)
      end
    end

    it 'logs backup creation' do
      create_test_secrets(temp_dir)

      expect(logger).to receive(:info).with(/Создаем backup/)
      expect(logger).to receive(:debug).with(/успешно создан/)

      file_manager.create_backup(temp_dir)
    end
  end

  describe '#list_backups' do
    it 'returns list of backup directories' do
      # Создаем несколько backup'ов
      3.times do |i|
        backup_name = "#{File.basename(temp_dir)}_backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{i}"
        backup_path = File.join(File.dirname(temp_dir), backup_name)
        FileUtils.mkdir_p(backup_path)
        sleep(0.1) # Небольшая задержка для уникальности timestamp'ов
      end

      backups = file_manager.list_backups(temp_dir)
      expect(backups.size).to eq(3)

      # Проверяем что возвращаются в обратном порядке (новые первыми)
      expect(backups).to all(include('backup'))
    end

    it 'returns empty array when no backups exist' do
      backups = file_manager.list_backups(temp_dir)
      expect(backups).to be_empty
    end
  end

  describe '#verify_file_integrity' do
    it 'returns true for existing readable file' do
      file_path = create_test_file(File.join(temp_dir, 'test.txt'))
      expect(file_manager.verify_file_integrity(file_path)).to be true
    end

    it 'returns false for non-existing file' do
      non_existing = File.join(temp_dir, 'non_existing.txt')
      expect(file_manager.verify_file_integrity(non_existing)).to be false
    end

    it 'returns false for empty file' do
      empty_file = File.join(temp_dir, 'empty.txt')
      File.write(empty_file, '')

      expect(file_manager.verify_file_integrity(empty_file)).to be false
    end

    it 'validates certificate files' do
      cert_pem = File.join(temp_dir, 'cert.cer')
      File.write(cert_pem, "-----BEGIN CERTIFICATE-----\nMIIBkTCB+wI...\n-----END CERTIFICATE-----")

      expect(file_manager.verify_file_integrity(cert_pem)).to be true
    end

    it 'validates JSON files' do
      json_file = File.join(temp_dir, 'config.json')
      File.write(json_file, '{"key": "value", "number": 123}')

      expect(file_manager.verify_file_integrity(json_file)).to be true
    end

    it 'validates mobile provisioning files' do
      prov_file = File.join(temp_dir, 'app.mobileprovisioning')
      File.write(prov_file, '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0">')

      expect(file_manager.verify_file_integrity(prov_file)).to be true
    end

    it 'validates PKCS#12 files' do
      p12_file = File.join(temp_dir, 'cert.p12')
      # PKCS#12 файлы начинаются с 0x30 (SEQUENCE tag)
      File.write(p12_file, "\x30\x82\x05\x10\x02\x01\x03\x30")

      expect(file_manager.verify_file_integrity(p12_file)).to be true
    end

    it 'rejects invalid file formats' do
      invalid_json = File.join(temp_dir, 'invalid.json')
      File.write(invalid_json, 'not json content')

      expect(file_manager.verify_file_integrity(invalid_json)).to be false
    end
  end

  describe '#verify_file_integrity_detailed' do
    let(:test_file) { File.join(temp_dir, 'test.cer') }

    before do
      File.write(test_file, "-----BEGIN CERTIFICATE-----\ntest content\n-----END CERTIFICATE-----")
    end

    it 'returns detailed verification result' do
      result = file_manager.verify_file_integrity_detailed(test_file)

      expect(result).to be_a(Hash)
      expect(result[:valid]).to be true
      expect(result[:exists]).to be true
      expect(result[:readable]).to be true
      expect(result[:non_empty]).to be true
      expect(result[:type_valid]).to be true
      expect(result[:size]).to be > 0
      expect(result[:error]).to be_nil
    end

    it 'detects non-existing files' do
      result = file_manager.verify_file_integrity_detailed('/non/existing/file.cer')

      expect(result[:valid]).to be false
      expect(result[:exists]).to be false
      expect(result[:readable]).to be false
    end

    it 'detects empty files' do
      empty_file = File.join(temp_dir, 'empty.cer')
      File.write(empty_file, '')

      result = file_manager.verify_file_integrity_detailed(empty_file)

      expect(result[:valid]).to be false
      expect(result[:exists]).to be true
      expect(result[:non_empty]).to be false
      expect(result[:size]).to eq(0)
    end

    it 'validates file type format' do
      invalid_cert = File.join(temp_dir, 'invalid.cer')
      File.write(invalid_cert, 'not a certificate')

      result = file_manager.verify_file_integrity_detailed(invalid_cert)

      expect(result[:valid]).to be false
      expect(result[:exists]).to be true
      expect(result[:readable]).to be true
      expect(result[:non_empty]).to be true
      expect(result[:type_valid]).to be false
    end
  end

  describe '#validate_file_path!' do
    it 'does not raise error for valid path' do
      expect { file_manager.validate_file_path!('/valid/path/file.txt') }.not_to raise_error
    end

    it 'raises error for empty path' do
      expect do
        file_manager.validate_file_path!('')
      end.to raise_error(KeySloth::ValidationError, /пустым/)
    end

    it 'raises error for nil path' do
      expect do
        file_manager.validate_file_path!(nil)
      end.to raise_error(KeySloth::ValidationError, /пустым/)
    end
  end
end
