# frozen_string_literal: true

require_relative 'keysloth/version'
require_relative 'keysloth/crypto'
require_relative 'keysloth/git_manager'
require_relative 'keysloth/file_manager'
require_relative 'keysloth/config'
require_relative 'keysloth/logger'
require_relative 'keysloth/errors'

# Основной модуль KeySloth - Ruby gem для управления зашифрованными секретами
#
# KeySloth предоставляет инструменты для безопасного хранения и управления
# секретами (сертификаты, ключи, конфигурационные файлы) в зашифрованном виде
# в Git репозиториях.
#
# @example Базовое использование
#   # Получение секретов из репозитория
#   KeySloth.pull(repo_url: 'git@github.com:company/secrets.git',
#                 branch: 'main',
#                 password: 'secret_password',
#                 local_path: './secrets')
#
#   # Отправка секретов в репозиторий
#   KeySloth.push(repo_url: 'git@github.com:company/secrets.git',
#                 branch: 'main',
#                 password: 'secret_password',
#                 local_path: './secrets')
#
# @example Использование с конфигурационным файлом
#   # Создайте файл .keyslothrc:
#   # repo_url: "git@github.com:company/secrets.git"
#   # branch: "main"
#   # local_path: "./secrets"
#
#   # Теперь достаточно указать только пароль:
#   KeySloth.pull(password: 'secret_password', config_file: '.keyslothrc')
#
# @example Обработка ошибок
#   begin
#     KeySloth.pull(repo_url: repo_url, password: password, local_path: './secrets')
#   rescue KeySloth::CryptoError => e
#     puts "Ошибка расшифровки: #{e.message}"
#   rescue KeySloth::RepositoryError => e
#     puts "Ошибка репозитория: #{e.message}"
#   rescue KeySloth::FileSystemError => e
#     puts "Ошибка файловой системы: #{e.message}"
#   end
#
# @example Использование в CI/CD с переменными окружения
#   # Установите переменные окружения:
#   # export SSH_PRIVATE_KEY="$(cat ~/.ssh/id_rsa)"
#   # export SECRET_PASSWORD="your_password"
#   # export GIT_AUTHOR_NAME="CI Bot"
#   # export GIT_AUTHOR_EMAIL="ci@company.com"
#
#   KeySloth.pull(
#     repo_url: 'git@github.com:company/secrets.git',
#     password: ENV['SECRET_PASSWORD'],
#     local_path: './secrets'
#   )
#
# @author KeySloth Team
# @since 0.1.0
module KeySloth
  class << self
    # Получает и расшифровывает секреты из удаленного Git репозитория
    #
    # @param repo_url [String] URL Git репозитория (SSH)
    # @param branch [String] Ветка для получения секретов (по умолчанию 'main')
    # @param password [String] Пароль для расшифровки секретов
    # @param local_path [String] Локальный путь для сохранения расшифрованных секретов
    # @param config_file [String, nil] Путь к файлу конфигурации (опционально)
    # @return [Boolean] true при успешном выполнении
    # @raise [KeySloth::RepositoryError] при ошибках работы с репозиторием
    # @raise [KeySloth::CryptoError] при ошибках расшифровки
    # @raise [KeySloth::FileSystemError] при ошибках файловой системы
    def pull(repo_url:, password:, local_path:, branch: 'main', config_file: nil)
      start_time = Time.now
      logger = Logger.new
      config = Config.load(config_file)

      # Аудит логирование начала операции
      logger.audit('pull_start', {
                     repo_url: repo_url,
                     branch: branch,
                     local_path: local_path,
                     config_file: config_file
                   })

      # Объединяем параметры с конфигурацией (параметры имеют приоритет, nil не перетирает)
      merged_config = config.merge({
        repo_url: repo_url,
        branch: branch,
        local_path: local_path
      }.compact)

      logger.info("Начинаем получение секретов из репозитория: #{repo_url}")

      git_manager = GitManager.new(merged_config[:repo_url], logger)
      # Прокидываем backup_count из конфигурации; невалидные значения заменяем дефолтом
      configured_backup_count = merged_config[:backup_count]
      backup_count = if configured_backup_count.is_a?(Integer) && configured_backup_count >= 0
                       configured_backup_count
                     else
                       KeySloth::FileManager::DEFAULT_BACKUP_COUNT
                     end
      file_manager = FileManager.new(logger, backup_count)
      crypto = Crypto.new(password, logger)

      # Создаем backup перед операцией
      if File.exist?(merged_config[:local_path])
        file_manager.create_backup(merged_config[:local_path])
      end

      # Клонируем/обновляем репозиторий и получаем зашифрованные файлы
      encrypted_files = git_manager.pull_encrypted_files(merged_config[:branch])

      # Создаем локальную директорию если не существует
      file_manager.ensure_directory(merged_config[:local_path])

      # Расшифровываем и сохраняем файлы с проверкой целостности
      integrity_failures = []

      encrypted_files.each do |encrypted_file|
        original_filename = encrypted_file[:name].gsub(/\.enc$/, '')

        # Проверяем целостность зашифрованного файла
        integrity_check = crypto.verify_integrity_detailed(encrypted_file[:content])

        unless integrity_check[:valid]
          error_msg = "Ошибка целостности для #{original_filename}: #{integrity_check[:error] || 'структура данных повреждена'}"
          logger.error(error_msg)
          integrity_failures << { file: original_filename, error: integrity_check[:error] }
          next
        end

        logger.debug("Проверка целостности пройдена для: #{original_filename}")

        # Расшифровываем файл
        decrypted_content = crypto.decrypt_file(encrypted_file[:content])
        local_file_path = File.join(merged_config[:local_path], original_filename)

        # Проверяем целостность расшифрованного файла
        if decrypted_content.nil? || decrypted_content.empty?
          logger.warn("Расшифрованный файл пустой: #{original_filename}")
        end

        file_manager.write_file(local_file_path, decrypted_content)
        logger.info("Расшифрован файл: #{original_filename} (размер: #{decrypted_content.length} байт)")
      end

      # Проверяем наличие ошибок целостности
      unless integrity_failures.empty?
        failure_details = integrity_failures.map { |f| "#{f[:file]}: #{f[:error]}" }.join('; ')
        raise CryptoError, "Обнаружены ошибки целостности файлов: #{failure_details}"
      end

      duration = Time.now - start_time
      logger.info("Успешно получено и расшифровано #{encrypted_files.size} файлов")

      # Аудит логирование успешного завершения
      logger.security_log('pull', :success, duration: duration, details: {
                            files_count: encrypted_files.size,
                            repo_url: repo_url,
                            branch: merged_config[:branch]
                          })

      true
    rescue StandardError => e
      duration = Time.now - start_time
      logger.security_log('pull', :failure, duration: duration, details: {
                            error: e.class.name,
                            repo_url: repo_url,
                            branch: branch
                          })
      raise
    ensure
      git_manager&.cleanup
    end

    # Шифрует и отправляет секреты в удаленный Git репозиторий
    #
    # @param repo_url [String] URL Git репозитория (SSH)
    # @param branch [String] Ветка для отправки секретов (по умолчанию 'main')
    # @param password [String] Пароль для шифрования секретов
    # @param local_path [String] Локальный путь с секретами для шифрования
    # @param config_file [String, nil] Путь к файлу конфигурации (опционально)
    # @param commit_message [String] Сообщение коммита (опционально)
    # @return [Boolean] true при успешном выполнении
    # @raise [KeySloth::RepositoryError] при ошибках работы с репозиторием
    # @raise [KeySloth::CryptoError] при ошибках шифрования
    # @raise [KeySloth::FileSystemError] при ошибках файловой системы
    def push(repo_url:, password:, local_path:, branch: 'main',
             config_file: nil, commit_message: nil)
      start_time = Time.now
      logger = Logger.new
      config = Config.load(config_file)

      # Аудит логирование начала операции
      logger.audit('push_start', {
                     repo_url: repo_url,
                     branch: branch,
                     local_path: local_path,
                     config_file: config_file,
                     commit_message: commit_message
                   })

      # Объединяем параметры с конфигурацией (параметры имеют приоритет, nil не перетирает)
      merged_config = config.merge({
        repo_url: repo_url,
        branch: branch,
        local_path: local_path
      }.compact)

      logger.info("Начинаем отправку секретов в репозиторий: #{repo_url}")

      git_manager = GitManager.new(merged_config[:repo_url], logger)
      configured_backup_count = merged_config[:backup_count]
      backup_count = if configured_backup_count.is_a?(Integer) && configured_backup_count >= 0
                       configured_backup_count
                     else
                       KeySloth::FileManager::DEFAULT_BACKUP_COUNT
                     end
      file_manager = FileManager.new(logger, backup_count)
      crypto = Crypto.new(password, logger)

      # Проверяем существование локальной директории
      unless file_manager.directory_exists?(merged_config[:local_path])
        raise FileSystemError, "Локальная директория не существует: #{merged_config[:local_path]}"
      end

      # Получаем список файлов для шифрования
      local_files = file_manager.collect_secret_files(merged_config[:local_path])

      if local_files.empty?
        logger.warn('Не найдено файлов секретов для отправки')
        return true
      end

      # Клонируем репозиторий и переключаемся на нужную ветку
      git_manager.prepare_repository(merged_config[:branch])

      # Шифруем и подготавливаем файлы
      encrypted_files = local_files.map do |file_path|
        content = file_manager.read_file(file_path)
        encrypted_content = crypto.encrypt_file(content)
        relative_path = file_manager.get_relative_path(file_path, merged_config[:local_path])
        encrypted_filename = "#{relative_path}.enc"

        {
          path: encrypted_filename,
          content: encrypted_content
        }
      end

      # Записываем зашифрованные файлы в репозиторий
      git_manager.write_encrypted_files(encrypted_files)

      # Создаем коммит и отправляем
      commit_msg = commit_message || "Update secrets: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      git_manager.commit_and_push(commit_msg, merged_config[:branch])

      duration = Time.now - start_time
      logger.info("Успешно зашифровано и отправлено #{encrypted_files.size} файлов")

      # Аудит логирование успешного завершения
      logger.security_log('push', :success, duration: duration, details: {
                            files_count: encrypted_files.size,
                            repo_url: repo_url,
                            branch: merged_config[:branch],
                            commit_message: commit_msg
                          })

      true
    rescue StandardError => e
      duration = Time.now - start_time
      logger.security_log('push', :failure, duration: duration, details: {
                            error: e.class.name,
                            repo_url: repo_url,
                            branch: branch
                          })
      raise
    ensure
      git_manager&.cleanup
    end
  end
end
