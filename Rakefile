# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# Настройка задач RSpec для тестирования
RSpec::Core::RakeTask.new(:spec) do |task|
  task.rspec_opts = '--format documentation --color'
end

# Настройка задач RuboCop для линтинга
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ['--display-cop-names']
end

# Задача для автоматического исправления RuboCop
RuboCop::RakeTask.new('rubocop:autocorrect') do |task|
  task.options = ['--autocorrect']
end

# Задача для установки зависимостей
desc 'Установить зависимости'
task :install do
  sh 'bundle install'
end

# Задача для сборки gem'а
desc 'Собрать gem'
task :build do
  sh 'gem build keysloth.gemspec'
end

# Задача для очистки временных файлов
desc 'Очистить временные файлы'
task :clean do
  FileUtils.rm_rf('tmp/')
  FileUtils.rm_rf('coverage/')
  FileUtils.rm_f(Dir.glob('*.gem'))
end

# Задача для полной проверки кода
desc 'Запустить все проверки (тесты + линтинг)'
task check: %i[rubocop spec]

# Задача для подготовки к релизу
desc 'Подготовить к релизу (проверки + сборка)'
task release_prepare: %i[clean check build]

# Задача для генерации документации
desc 'Генерировать YARD документацию'
task :docs do
  sh 'yard doc'
end

# Задача по умолчанию
task default: :check

# Задачи для разработки
namespace :dev do
  desc 'Установить git hooks для разработки'
  task :setup_hooks do
    hook_content = <<~HOOK
      #!/bin/sh
      echo "Запускаем проверки перед коммитом..."
      bundle exec rake rubocop || exit 1
      bundle exec rake spec || exit 1
      echo "Все проверки пройдены успешно!"
    HOOK

    hook_path = '.git/hooks/pre-commit'
    File.write(hook_path, hook_content)
    File.chmod(0o755, hook_path)
    puts 'Git pre-commit hook установлен'
  end

  desc 'Запустить интерактивную консоль'
  task :console do
    require_relative 'lib/keysloth'
    require 'pry'
    Pry.start
  end
end

# Задачи для CI/CD
namespace :ci do
  desc 'Запустить тесты с покрытием кода'
  task :test_coverage do
    ENV['COVERAGE'] = 'true'
    Rake::Task[:spec].invoke
  end

  desc 'Проверить безопасность зависимостей'
  task :security do
    sh 'bundle audit check --update'
  rescue StandardError => e
    puts "Предупреждение: проверка безопасности не прошла: #{e.message}"
  end
end
