# frozen_string_literal: true

require_relative 'lib/keysloth/version'

Gem::Specification.new do |spec|
  spec.name = 'keysloth'
  spec.version = KeySloth::VERSION
  spec.authors = ['KeySloth Team']
  spec.email = ['team@keysloth.org']

  spec.summary = 'Ruby gem для управления зашифрованными секретами в Git репозиториях'
  spec.description = <<~DESC
    KeySloth - инструмент для безопасного хранения и управления секретами (сертификаты,#{' '}
    ключи, конфигурационные файлы) в зашифрованном виде в Git репозиториях.#{' '}
    Обеспечивает простое получение, изменение и отправку секретов с использованием#{' '}
    AES-256-GCM шифрования.
  DESC
  spec.homepage = 'https://github.com/keysloth/keysloth'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/keysloth/keysloth'
  spec.metadata['changelog_uri'] = 'https://github.com/keysloth/keysloth/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Определяем, какие файлы включить в gem
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.start_with?('spec/', 'test/', 'features/', '.git', 'appveyor', 'Gemfile')
    end
  end

  spec.bindir = 'bin'
  spec.executables = ['keysloth']
  spec.require_paths = ['lib']

  # Основные зависимости
  spec.add_dependency 'thor', '~> 1.2' # CLI интерфейс
  # Используем системные git команды вместо rugged для упрощения установки
  # Используем встроенный openssl, доступный в Ruby по умолчанию

  # Зависимости для разработки
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.50'
  spec.add_development_dependency 'rubocop-performance', '~> 1.17'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.20'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'yard', '~> 0.9'
end
