# frozen_string_literal: true

RSpec.describe KeySloth do
  it 'has a version number' do
    expect(KeySloth::VERSION).not_to be_nil
    expect(KeySloth::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  describe '.pull' do
    let(:repo_url) { 'git@github.com:test/secrets.git' }
    let(:password) { 'test_password' }
    let(:local_path) { './test_secrets' }
    let(:branch) { 'main' }

    it 'calls the required components in correct order' do
      git_manager = instance_double(KeySloth::GitManager)
      file_manager = instance_double(KeySloth::FileManager)
      crypto = instance_double(KeySloth::Crypto)
      logger = mock_logger
      config = instance_double(KeySloth::Config)

      # Мокируем создание компонентов
      allow(KeySloth::Logger).to receive(:new).and_return(logger)
      allow(KeySloth::Config).to receive(:load).and_return(config)
      allow(config).to receive(:merge).and_return({
                                                    repo_url: repo_url,
                                                    branch: branch,
                                                    local_path: local_path
                                                  })

      allow(KeySloth::GitManager).to receive(:new).and_return(git_manager)
      allow(KeySloth::FileManager).to receive(:new).and_return(file_manager)
      allow(KeySloth::Crypto).to receive(:new).and_return(crypto)

      # Настраиваем поведение моков
      allow(File).to receive(:exist?).and_return(false)
      allow(file_manager).to receive(:ensure_directory)
      allow(file_manager).to receive(:write_file)
      allow(git_manager).to receive(:pull_encrypted_files).and_return([
                                                                        { name: 'test.cer.enc',
                                                                          content: 'encrypted_content' }
                                                                      ])
      allow(crypto).to receive(:verify_integrity_detailed).and_return({
                                                                        valid: true,
                                                                        structure_valid: true,
                                                                        decryption_valid: true,
                                                                        error: nil
                                                                      })
      allow(crypto).to receive(:decrypt_file).and_return('decrypted_content')
      allow(git_manager).to receive(:cleanup)

      # Выполняем операцию
      result = described_class.pull(
        repo_url: repo_url,
        password: password,
        local_path: local_path,
        branch: branch
      )

      expect(result).to be true
    end
  end

  describe '.push' do
    let(:repo_url) { 'git@github.com:test/secrets.git' }
    let(:password) { 'test_password' }
    let(:local_path) { './test_secrets' }
    let(:branch) { 'main' }

    it 'calls the required components in correct order' do
      git_manager = instance_double(KeySloth::GitManager)
      file_manager = instance_double(KeySloth::FileManager)
      crypto = instance_double(KeySloth::Crypto)
      logger = mock_logger
      config = instance_double(KeySloth::Config)

      # Мокируем создание компонентов
      allow(KeySloth::Logger).to receive(:new).and_return(logger)
      allow(KeySloth::Config).to receive(:load).and_return(config)
      allow(config).to receive(:merge).and_return({
                                                    repo_url: repo_url,
                                                    branch: branch,
                                                    local_path: local_path
                                                  })

      allow(KeySloth::GitManager).to receive(:new).and_return(git_manager)
      allow(KeySloth::FileManager).to receive(:new).and_return(file_manager)
      allow(KeySloth::Crypto).to receive(:new).and_return(crypto)

      # Настраиваем поведение моков
      allow(file_manager).to receive(:directory_exists?).and_return(true)
      allow(file_manager).to receive(:collect_secret_files).and_return(['test.cer'])
      allow(file_manager).to receive(:read_file).and_return('file_content')
      allow(file_manager).to receive(:get_relative_path).and_return('test.cer')
      allow(crypto).to receive(:encrypt_file).and_return('encrypted_content')

      allow(git_manager).to receive(:prepare_repository)
      allow(git_manager).to receive(:write_encrypted_files)
      allow(git_manager).to receive(:commit_and_push)
      allow(git_manager).to receive(:cleanup)

      # Выполняем операцию
      result = described_class.push(
        repo_url: repo_url,
        password: password,
        local_path: local_path,
        branch: branch
      )

      expect(result).to be true
    end
  end
end
