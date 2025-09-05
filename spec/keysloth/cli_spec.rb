# frozen_string_literal: true

require 'thor'
require 'stringio'
require_relative '../../lib/keysloth/cli'

RSpec.describe KeySloth::CLI do
  let(:cli) { described_class.new }
  let(:output) { StringIO.new }
  let(:logger) { mock_logger }

  before do
    # Redirect stdout to capture command output
    allow($stdout).to receive(:write) { |str| output.write(str) }
    allow($stdout).to receive(:puts) { |str| output.puts(str) }

    # Mock logger creation
    allow(KeySloth::Logger).to receive(:new).and_return(logger)
  end

  describe '#pull' do
    let(:repo_url) { 'git@github.com:test/secrets.git' }
    let(:password) { 'test_password' }
    let(:args) { ['pull', '--repo', repo_url, '--password', password] }

    before do
      allow(KeySloth).to receive(:pull).and_return(true)
    end

    it 'calls KeySloth.pull with provided or nil parameters (no defaults from CLI)' do
      cli.invoke(:pull, [], {
                   repo: repo_url,
                   password: password,
                   branch: nil,
                   path: nil,
                   config: nil
                 })

      expect(KeySloth).to have_received(:pull).with(
        repo_url: repo_url,
        branch: nil,
        password: password,
        local_path: nil,
        config_file: nil
      )
    end

    it 'uses custom branch when provided' do
      cli.invoke(:pull, [], {
                   repo: repo_url,
                   password: password,
                   branch: 'develop',
                   path: './secrets'
                 })

      expect(KeySloth).to have_received(:pull).with(
        repo_url: repo_url,
        branch: 'develop',
        password: password,
        local_path: './secrets',
        config_file: nil
      )
    end

    it 'uses custom path when provided' do
      cli.invoke(:pull, [], {
                   repo: repo_url,
                   password: password,
                   path: './custom_secrets'
                 })

      expect(KeySloth).to have_received(:pull).with(
        repo_url: repo_url,
        branch: nil,
        password: password,
        local_path: './custom_secrets',
        config_file: nil
      )
    end

    it 'passes config file when provided' do
      cli.invoke(:pull, [], {
                   repo: repo_url,
                   password: password,
                   config: '.custom_keyslothrc'
                 })

      expect(KeySloth).to have_received(:pull).with(
        repo_url: repo_url,
        branch: nil,
        password: password,
        local_path: nil,
        config_file: '.custom_keyslothrc'
      )
    end

    it 'logs operation start and completion' do
      cli.invoke(:pull, [], {
                   repo: repo_url,
                   password: password
                 })

      expect(logger).to have_received(:info).with(/Начинаем операцию получения секретов/)
      expect(logger).to have_received(:info).with(/завершена успешно/)
    end

    it 'handles KeySloth errors and exits' do
      allow(KeySloth).to receive(:pull).and_raise(KeySloth::CryptoError.new('Test error'))

      expect do
        cli.invoke(:pull, [], {
                     repo: repo_url,
                     password: password
                   })
      end.to raise_error(SystemExit)

      expect(logger).to have_received(:error).with(/Ошибка выполнения операции: Test error/)
    end
  end

  describe '#push' do
    let(:repo_url) { 'git@github.com:test/secrets.git' }
    let(:password) { 'test_password' }

    before do
      allow(KeySloth).to receive(:push).and_return(true)
    end

    it 'calls KeySloth.push with provided or nil parameters (no defaults from CLI)' do
      cli.invoke(:push, [], {
                   repo: repo_url,
                   password: password,
                   branch: nil,
                   path: nil,
                   message: nil
                 })

      expect(KeySloth).to have_received(:push).with(
        repo_url: repo_url,
        branch: nil,
        password: password,
        local_path: nil,
        config_file: nil,
        commit_message: nil
      )
    end

    it 'passes commit message when provided' do
      cli.invoke(:push, [], {
                   repo: repo_url,
                   password: password,
                   message: 'Custom commit message'
                 })

      expect(KeySloth).to have_received(:push).with(
        repo_url: repo_url,
        branch: nil,
        password: password,
        local_path: nil,
        config_file: nil,
        commit_message: 'Custom commit message'
      )
    end

    it 'logs operation progress' do
      cli.invoke(:push, [], {
                   repo: repo_url,
                   password: password
                 })

      expect(logger).to have_received(:info).with(/Начинаем операцию отправки секретов/)
      expect(logger).to have_received(:info).with(/завершена успешно/)
    end

    it 'handles errors gracefully' do
      allow(KeySloth).to receive(:push).and_raise(KeySloth::RepositoryError.new('Network error'))

      expect do
        cli.invoke(:push, [], {
                     repo: repo_url,
                     password: password
                   })
      end.to raise_error(SystemExit)

      expect(logger).to have_received(:error).with(/Ошибка выполнения операции: Network error/)
    end
  end

  describe '#status' do
    let(:file_manager) { instance_double(KeySloth::FileManager) }
    let(:secret_files) { ['/path/to/cert.cer', '/path/to/config.json'] }

    before do
      allow(KeySloth::FileManager).to receive(:new).and_return(file_manager)
      allow(file_manager).to receive(:get_relative_path).and_return('cert.cer', 'config.json')
      allow(file_manager).to receive_messages(directory_exists?: true,
                                              collect_secret_files: secret_files, verify_file_integrity: true, list_backups: [])
      allow(File).to receive(:size).and_return(1024)
    end

    it 'shows status of secret files' do
      cli.invoke(:status, [], { path: './secrets' })

      expect(file_manager).to have_received(:collect_secret_files).with('./secrets')
      expect(logger).to have_received(:info).with(/Найдено 2 файлов секретов/)
      expect(logger).to have_received(:info).with(/cert\.cer.*1024 байт/)
      expect(logger).to have_received(:info).with(/config\.json.*1024 байт/)
    end

    it 'warns when secrets directory does not exist' do
      allow(file_manager).to receive(:directory_exists?).and_return(false)

      cli.invoke(:status, [], { path: './nonexistent' })

      expect(logger).to have_received(:warn).with(/Директория секретов не существует/)
    end

    it 'handles empty secrets directory' do
      allow(file_manager).to receive(:collect_secret_files).and_return([])

      cli.invoke(:status, [], { path: './secrets' })

      expect(logger).to have_received(:info).with('Файлы секретов не найдены')
    end

    it 'shows backup information' do
      backups = ['/path/secrets_backup_20231201_120000', '/path/secrets_backup_20231201_110000']
      allow(file_manager).to receive(:list_backups).and_return(backups)

      cli.invoke(:status, [], { path: './secrets' })

      expect(logger).to have_received(:info).with(/Доступные резервные копии/)
    end

    it 'uses local_path from config when path option is not provided' do
      allow(KeySloth::Config).to receive(:load).and_return(instance_double(KeySloth::Config, to_h: {}, merge: { local_path: './conf_secrets' }))

      cli.invoke(:status, [], { config: '.keyslothrc' })

      expect(file_manager).to have_received(:collect_secret_files).with('./conf_secrets')
    end
  end

  describe '#validate' do
    let(:file_manager) { instance_double(KeySloth::FileManager) }
    let(:secret_files) { ['/path/to/cert.cer', '/path/to/config.json'] }

    before do
      allow(KeySloth::FileManager).to receive(:new).and_return(file_manager)
      allow(file_manager).to receive_messages(directory_exists?: true,
                                              collect_secret_files: secret_files)
      allow(file_manager).to receive(:get_relative_path).and_return('cert.cer', 'config.json')
      allow(file_manager).to receive(:verify_file_integrity).and_return(true, true)
    end

    it 'validates all secret files' do
      cli.invoke(:validate, [], { path: './secrets' })

      expect(file_manager).to have_received(:verify_file_integrity).twice
      expect(logger).to have_received(:info).with(/Проверяем 2 файлов секретов/)
      expect(logger).to have_received(:info).with(/✓ cert\.cer - файл корректен/)
      expect(logger).to have_received(:info).with(/✓ config\.json - файл корректен/)
      expect(logger).to have_received(:info).with(/Корректных файлов: 2/)
      expect(logger).to have_received(:info).with(/Поврежденных файлов: 0/)
    end

    it 'detects corrupted files' do
      allow(file_manager).to receive(:verify_file_integrity).and_return(true, false)

      cli.invoke(:validate, [], { path: './secrets' })

      expect(logger).to have_received(:info).with(/✓ cert\.cer - файл корректен/)
      expect(logger).to have_received(:error).with(/✗ config\.json - файл поврежден/)
      expect(logger).to have_received(:info).with(/Корректных файлов: 1/)
      expect(logger).to have_received(:info).with(/Поврежденных файлов: 1/)
    end

    it 'exits with error code when corrupted files found' do
      allow(file_manager).to receive(:verify_file_integrity).and_return(false)

      expect do
        cli.invoke(:validate, [], { path: './secrets' })
      end.to raise_error(SystemExit)

      expect(logger).to have_received(:error).with(/Обнаружены поврежденные файлы/)
    end

    it 'exits with error when secrets directory does not exist' do
      allow(file_manager).to receive(:directory_exists?).and_return(false)

      expect do
        cli.invoke(:validate, [], { path: './nonexistent' })
      end.to raise_error(SystemExit)

      expect(logger).to have_received(:error).with(/Директория секретов не существует/)
    end

    it 'uses local_path from config when path option is not provided' do
      allow(KeySloth::Config).to receive(:load).and_return(instance_double(KeySloth::Config, to_h: {}, merge: { local_path: './conf_secrets' }))
      allow(file_manager).to receive(:verify_file_integrity).and_return(true)

      cli.invoke(:validate, [], { config: '.keyslothrc' })

      expect(file_manager).to have_received(:collect_secret_files).with('./conf_secrets')
    end
  end

  describe '#restore' do
    let(:file_manager) { instance_double(KeySloth::FileManager) }
    let(:backup_path) { '/path/to/backup' }

    before do
      allow(KeySloth::FileManager).to receive(:new).and_return(file_manager)
      allow(file_manager).to receive(:restore_from_backup)
    end

    it 'restores from specified backup' do
      cli.invoke(:restore, [backup_path], { path: './secrets' })

      expect(file_manager).to have_received(:restore_from_backup).with(backup_path, './secrets')
      expect(logger).to have_received(:info).with(/Восстанавливаем секреты из резервной копии/)
      expect(logger).to have_received(:info).with(/Восстановление завершено успешно/)
    end

    it 'handles restoration errors' do
      allow(file_manager).to receive(:restore_from_backup).and_raise(KeySloth::FileSystemError.new('Backup not found'))

      expect do
        cli.invoke(:restore, [backup_path], { path: './secrets' })
      end.to raise_error(SystemExit)

      expect(logger).to have_received(:error).with(/Ошибка восстановления: Backup not found/)
    end

    it 'uses local_path from config when path option is not provided' do
      allow(KeySloth::Config).to receive(:load).and_return(instance_double(KeySloth::Config, to_h: {}, merge: { local_path: './conf_secrets' }))

      cli.invoke(:restore, [backup_path], { config: '.keyslothrc' })

      expect(file_manager).to have_received(:restore_from_backup).with(backup_path, './conf_secrets')
    end
  end

  describe '#init' do
    let(:file_manager) { instance_double(KeySloth::FileManager) }
    let(:repo_url) { 'git@github.com:test/secrets.git' }

    before do
      allow(KeySloth::FileManager).to receive(:new).and_return(file_manager)
      allow(file_manager).to receive(:ensure_directory)
      allow(File).to receive(:write)
      allow(File).to receive_messages(exist?: false, read: '')
    end

    it 'creates configuration and directories' do
      cli.invoke(:init, [], {
                   repo: repo_url,
                   branch: 'main',
                   path: './secrets',
                   force: false
                 })

      expect(File).to have_received(:write).with('.keyslothrc', anything)
      expect(file_manager).to have_received(:ensure_directory).with('./secrets')
      expect(logger).to have_received(:info).with(/Создан файл конфигурации/)
      expect(logger).to have_received(:info).with(/Создана директория для секретов/)
    end

    it 'refuses to overwrite existing config without force' do
      allow(File).to receive(:exist?).with('.keyslothrc').and_return(true)

      expect do
        cli.invoke(:init, [], {
                     repo: repo_url,
                     force: false
                   })
      end.to raise_error(SystemExit)

      expect(logger).to have_received(:error).with(/уже существует.*--force/)
    end

    it 'overwrites existing config with force flag' do
      allow(File).to receive(:exist?).with('.keyslothrc').and_return(true)

      cli.invoke(:init, [], {
                   repo: repo_url,
                   force: true
                 })

      expect(File).to have_received(:write).with('.keyslothrc', anything)
      expect(logger).to have_received(:info).with(/Создан файл конфигурации/)
    end

    it 'updates .gitignore with secrets path' do
      allow(File).to receive(:exist?).with('.gitignore').and_return(false)

      cli.invoke(:init, [], {
                   repo: repo_url,
                   path: './custom_secrets'
                 })

      expect(File).to have_received(:write).with('.gitignore', /custom_secrets/)
    end
  end

  describe '#version' do
    it 'displays current version' do
      cli.invoke(:version)

      expect(output.string).to include("KeySloth версия #{KeySloth::VERSION}")
    end
  end

  describe '#help' do
    it 'displays general help without arguments' do
      cli.invoke(:help)

      expect(output.string).to include('KeySloth v')
      expect(output.string).to include('ИСПОЛЬЗОВАНИЕ:')
      expect(output.string).to include('КОМАНДЫ:')
      expect(output.string).to include('pull')
      expect(output.string).to include('push')
    end

    it 'displays command-specific help with argument' do
      # Thor's help system will handle this automatically
      expect { cli.invoke(:help, ['pull']) }.not_to raise_error
    end
  end

  describe 'logger setup' do
    it 'sets up debug logger with verbose flag' do
      expect(KeySloth::Logger).to receive(:new).with(level: :debug)

      cli.options = { verbose: true }
      cli.send(:setup_logger)
    end

    it 'sets up error logger with quiet flag' do
      expect(KeySloth::Logger).to receive(:new).with(level: :error)

      cli.options = { quiet: true }
      cli.send(:setup_logger)
    end

    it 'sets up default info logger' do
      expect(KeySloth::Logger).to receive(:new).with(level: :info)

      cli.options = {}
      cli.send(:setup_logger)
    end
  end

  describe 'option parsing' do
    it 'parses global options correctly' do
      # This would be tested through Thor's option parsing
      # which is already well-tested by the Thor gem
      expect(described_class.class_options.keys).to include(:verbose, :quiet, :config)
    end
  end
end
