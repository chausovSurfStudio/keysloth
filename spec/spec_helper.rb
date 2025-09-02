# frozen_string_literal: true

require 'bundler/setup'
require 'simplecov'
require 'webmock/rspec'
require 'timecop'

# Настройка SimpleCov для покрытия кода
if ENV['COVERAGE']
  SimpleCov.start do
    add_filter '/spec/'
    add_filter '/vendor/'

    add_group 'Core', 'lib/keysloth.rb'
    add_group 'Crypto', 'lib/keysloth/crypto.rb'
    add_group 'Git', 'lib/keysloth/git_manager.rb'
    add_group 'Files', 'lib/keysloth/file_manager.rb'
    add_group 'CLI', 'lib/keysloth/cli.rb'
    add_group 'Other', 'lib/keysloth/'

    minimum_coverage 90
  end
end

require 'keysloth'

# Настройка WebMock для мокирования HTTP запросов
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  # Включение фильтров и предупреждений
  config.disable_monkey_patching!
  config.warnings = true

  # Настройка ожиданий
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Настройка моков
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Настройка профилирования тестов
  config.profile_examples = 10

  # Случайный порядок выполнения тестов
  config.order = :random
  Kernel.srand config.seed

  # Настройка shared context
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Очистка после каждого теста
  config.after do
    # Возвращаем время в исходное состояние
    Timecop.return

    # Очищаем переменные окружения
    ENV.delete('SSH_PRIVATE_KEY')
    ENV.delete('SSH_PUBLIC_KEY')
    ENV.delete('GIT_AUTHOR_NAME')
    ENV.delete('GIT_AUTHOR_EMAIL')
  end

  # Хелперы для тестов
  config.include(Module.new do
    # Создает временную директорию для тестов
    def create_temp_dir
      Dir.mktmpdir('keysloth_test_')
    end

    # Создает тестовый файл с содержимым
    def create_test_file(path, content = 'test content')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    # Создает тестовые файлы секретов
    def create_test_secrets(base_path)
      secrets = {
        'test.cer' => 'certificate content',
        'app.p12' => 'p12 certificate content',
        'profile.mobileprovisioning' => 'provisioning profile content',
        'config.json' => '{"key": "value"}'
      }

      secrets.each do |filename, content|
        create_test_file(File.join(base_path, filename), content)
      end

      secrets
    end

    # Мокирует SSH ключи в переменных окружения
    def mock_ssh_keys
      ENV['SSH_PRIVATE_KEY'] = <<~PRIVATE_KEY
        -----BEGIN OPENSSH PRIVATE KEY-----
        test_private_key_content
        -----END OPENSSH PRIVATE KEY-----
      PRIVATE_KEY

      ENV['SSH_PUBLIC_KEY'] = 'ssh-rsa test_public_key_content test@example.com'
    end

    # Создает мок логгера
    def mock_logger
      logger = instance_double(KeySloth::Logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:debug)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:error)
      allow(logger).to receive(:audit)
      allow(logger).to receive(:security_log)
      logger
    end
  end)
end
