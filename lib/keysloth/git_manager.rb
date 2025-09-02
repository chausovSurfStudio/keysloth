# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'open3'

module KeySloth
  # Класс для управления Git операциями KeySloth
  #
  # Обеспечивает клонирование репозиториев, работу с ветками,
  # коммиты и отправку изменений. Использует SSH ключи для аутентификации.
  #
  # @example Использование
  #   git_manager = KeySloth::GitManager.new('git@github.com:company/secrets.git')
  #
  #   # Получение зашифрованных файлов
  #   files = git_manager.pull_encrypted_files('main')
  #
  #   # Подготовка репозитория для записи
  #   git_manager.prepare_repository('main')
  #
  #   # Запись и отправка файлов
  #   git_manager.write_encrypted_files(encrypted_files)
  #   git_manager.commit_and_push('Update secrets', 'main')
  #
  # @author KeySloth Team
  # @since 0.1.0
  class GitManager
    # Инициализация менеджера Git операций
    #
    # @param repo_url [String] URL Git репозитория (SSH)
    # @param logger [KeySloth::Logger] Логгер для вывода сообщений
    # @raise [RepositoryError] при некорректном URL репозитория
    def initialize(repo_url, logger = nil)
      @repo_url = repo_url&.to_s
      @logger = logger || Logger.new(level: :error)
      @temp_dir = nil

      validate_repo_url!
      check_git_available!
    end

    # Получает зашифрованные файлы из репозитория
    #
    # @param branch [String] Ветка для получения файлов (по умолчанию 'main')
    # @return [Array<Hash>] Массив хешей с данными файлов
    #   Каждый хеш содержит:
    #   - :name [String] Имя файла
    #   - :content [String] Содержимое файла
    # @raise [RepositoryError] при ошибках работы с репозиторием
    def pull_encrypted_files(branch = 'main')
      @logger.info("Клонируем репозиторий: #{@repo_url}")

      begin
        clone_repository
        checkout_branch(branch)

        files = collect_encrypted_files
        @logger.info("Найдено #{files.size} зашифрованных файлов")

        files
      rescue Rugged::Error => e
        @logger.error('Ошибка работы с Git репозиторием', e)
        raise RepositoryError, "Git операция не удалась: #{e.message}"
      rescue StandardError => e
        @logger.error('Неожиданная ошибка при получении файлов', e)
        raise RepositoryError, "Не удалось получить файлы: #{e.message}"
      end
    end

    # Подготавливает репозиторий для записи изменений
    #
    # @param branch [String] Ветка для работы
    # @raise [RepositoryError] при ошибках подготовки репозитория
    def prepare_repository(branch = 'main')
      @logger.info("Подготавливаем репозиторий для записи в ветку: #{branch}")

      begin
        clone_repository
        checkout_branch(branch)

        # Проверяем актуальность ветки
        check_branch_up_to_date(branch)
      rescue Rugged::Error => e
        @logger.error('Ошибка подготовки репозитория', e)
        raise RepositoryError, "Не удалось подготовить репозиторий: #{e.message}"
      end
    end

    # Записывает зашифрованные файлы в репозиторий
    #
    # @param encrypted_files [Array<Hash>] Массив зашифрованных файлов
    #   Каждый хеш должен содержать:
    #   - :path [String] Относительный путь файла в репозитории
    #   - :content [String] Зашифрованное содержимое файла
    # @raise [RepositoryError] при ошибках записи файлов
    def write_encrypted_files(encrypted_files)
      @logger.info("Записываем #{encrypted_files.size} зашифрованных файлов")

      begin
        # Очищаем существующие .enc файлы
        clear_encrypted_files

        # Записываем новые зашифрованные файлы
        encrypted_files.each do |file_data|
          file_path = File.join(@temp_dir, file_data[:path])

          # Создаем директорию если не существует
          FileUtils.mkdir_p(File.dirname(file_path))

          # Записываем файл
          File.write(file_path, file_data[:content])
          @logger.debug("Записан файл: #{file_data[:path]}")
        end
      rescue StandardError => e
        @logger.error('Ошибка записи зашифрованных файлов', e)
        raise RepositoryError, "Не удалось записать файлы: #{e.message}"
      end
    end

    # Создает коммит и отправляет изменения в репозиторий
    #
    # @param commit_message [String] Сообщение коммита
    # @param branch [String] Ветка для отправки
    # @raise [RepositoryError] при ошибках коммита или отправки
    def commit_and_push(commit_message, branch = 'main')
      @logger.info("Создаем коммит и отправляем в ветку: #{branch}")

      begin
        # Добавляем все изменения в индекс
        add_all_changes

        # Проверяем есть ли изменения
        unless has_changes?
          @logger.info('Нет изменений для коммита')
          return
        end

        # Создаем коммит
        create_commit(commit_message)

        # Отправляем в удаленный репозиторий
        push_to_remote(branch)

        @logger.info('Изменения успешно отправлены в репозиторий')
      rescue Rugged::Error => e
        @logger.error('Ошибка коммита или отправки', e)
        raise RepositoryError, "Не удалось отправить изменения: #{e.message}"
      end
    end

    # Очищает временные файлы
    def cleanup
      return unless @temp_dir && Dir.exist?(@temp_dir)

      @logger.debug("Очищаем временную директорию: #{@temp_dir}")
      FileUtils.remove_entry(@temp_dir)
      @temp_dir = nil
    end

    private

    # Валидирует URL репозитория
    #
    # @raise [RepositoryError] при некорректном URL
    def validate_repo_url!
      if @repo_url.nil? || @repo_url.empty?
        raise RepositoryError, 'URL репозитория не может быть пустым'
      end

      unless @repo_url.match?(%r{\A[\w\-\.]+@[\w\-\.]+:[\w\-\./]+\.git\z})
        raise RepositoryError, 'Поддерживаются только SSH URL репозиториев (git@host:repo.git)'
      end
    end

    # Проверяет доступность git команды
    #
    # @raise [RepositoryError] если git недоступен
    def check_git_available!
      _, _, status = Open3.capture3('git --version')
      raise RepositoryError, 'Git не установлен или недоступен в системе' unless status.success?
    end

    # Клонирует репозиторий во временную директорию
    #
    # @raise [RepositoryError] при ошибках клонирования
    def clone_repository
      return if @repository

      @temp_dir = Dir.mktmpdir('keysloth_repo_')
      @logger.debug("Создана временная директория: #{@temp_dir}")

      credentials = create_ssh_credentials

      @repository = Rugged::Repository.clone_at(
        @repo_url,
        @temp_dir,
        credentials: credentials
      )

      @logger.debug('Репозиторий успешно клонирован')
    end

    # Переключается на указанную ветку
    #
    # @param branch [String] Имя ветки
    # @raise [RepositoryError] при ошибках переключения ветки
    def checkout_branch(branch)
      @logger.debug("Переключаемся на ветку: #{branch}")

      # Ищем локальную ветку
      local_branch = @repository.branches["#{branch}"]

      if local_branch
        @repository.checkout(local_branch)
      else
        # Ищем удаленную ветку и создаем локальную
        remote_branch = @repository.branches["origin/#{branch}"]

        if remote_branch
          @repository.create_branch(branch, remote_branch.target)
          @repository.checkout(branch)
        else
          raise RepositoryError, "Ветка '#{branch}' не найдена в репозитории"
        end
      end

      @logger.debug("Успешно переключились на ветку: #{branch}")
    end

    # Проверяет актуальность локальной ветки
    #
    # @param branch [String] Имя ветки
    # @raise [RepositoryError] если ветка не актуальна
    def check_branch_up_to_date(branch)
      local_branch = @repository.branches[branch]
      remote_branch = @repository.branches["origin/#{branch}"]

      return unless local_branch && remote_branch

      if local_branch.target_id != remote_branch.target_id
        raise RepositoryError,
              "Локальная ветка '#{branch}' не синхронизирована с удаленной. " \
              'Выполните pull для получения последних изменений.'
      end
    end

    # Собирает все зашифрованные файлы из репозитория
    #
    # @return [Array<Hash>] Массив данных файлов
    def collect_encrypted_files
      files = []

      @repository.index.each do |entry|
        next unless entry[:path].end_with?('.enc')

        blob = @repository.lookup(entry[:oid])
        files << {
          name: entry[:path],
          content: blob.content
        }
      end

      files
    end

    # Очищает существующие зашифрованные файлы
    def clear_encrypted_files
      @logger.debug('Очищаем существующие .enc файлы')

      Dir.glob(File.join(@temp_dir, '**/*.enc')).each do |file_path|
        File.delete(file_path)
        @logger.debug("Удален файл: #{File.basename(file_path)}")
      end
    end

    # Добавляет все изменения в индекс Git
    def add_all_changes
      @repository.index.add_all
      @repository.index.write
    end

    # Проверяет наличие изменений
    #
    # @return [Boolean] true если есть изменения
    def has_changes?
      !@repository.diff_workdir_to_index.deltas.empty? ||
        !@repository.diff_index_to_tree(@repository.head.target.tree).deltas.empty?
    end

    # Создает коммит
    #
    # @param message [String] Сообщение коммита
    def create_commit(message)
      signature = create_commit_signature

      Rugged::Commit.create(
        @repository,
        author: signature,
        committer: signature,
        message: message,
        parents: [@repository.head.target],
        tree: @repository.index.write_tree(@repository)
      )

      @logger.debug("Создан коммит: #{message}")
    end

    # Отправляет изменения в удаленный репозиторий
    #
    # @param branch [String] Имя ветки
    def push_to_remote(branch)
      credentials = create_ssh_credentials

      @repository.push('origin', ["refs/heads/#{branch}"], credentials: credentials)
      @logger.debug("Изменения отправлены в origin/#{branch}")
    end

    # Создает SSH credentials для аутентификации
    #
    # @return [Rugged::Credentials::SshKey] SSH ключи
    def create_ssh_credentials
      ssh_key_path = File.expand_path('~/.ssh/id_rsa')
      ssh_pub_key_path = File.expand_path('~/.ssh/id_rsa.pub')

      # Проверяем наличие SSH ключей в переменных окружения (для CI/CD)
      if ENV['SSH_PRIVATE_KEY']
        # В CI/CD окружении используем ключи из переменных окружения
        return create_ssh_key_from_env
      end

      # Локальная работа - используем стандартные SSH ключи
      unless File.exist?(ssh_key_path)
        raise AuthenticationError, "SSH ключ не найден: #{ssh_key_path}"
      end

      Rugged::Credentials::SshKey.new(
        username: 'git',
        publickey: ssh_pub_key_path,
        privatekey: ssh_key_path
      )
    end

    # Создает SSH ключи из переменных окружения для CI/CD
    #
    # Используется в автоматизированных средах где SSH ключи передаются
    # через переменные окружения SSH_PRIVATE_KEY и SSH_PUBLIC_KEY.
    # Создает временные файлы для ключей с правильными правами доступа.
    #
    # @return [Rugged::Credentials::SshKey] Объект SSH ключей для аутентификации
    # @raise [AuthenticationError] если SSH_PRIVATE_KEY не установлен
    # @example Использование в CI/CD
    #   ENV['SSH_PRIVATE_KEY'] = File.read('~/.ssh/id_rsa')
    #   ENV['SSH_PUBLIC_KEY'] = File.read('~/.ssh/id_rsa.pub')
    #   credentials = create_ssh_key_from_env
    def create_ssh_key_from_env
      private_key = ENV.fetch('SSH_PRIVATE_KEY', nil)
      public_key = ENV.fetch('SSH_PUBLIC_KEY', nil)

      raise AuthenticationError, 'SSH_PRIVATE_KEY не установлен' unless private_key

      # Создаем временные файлы для ключей
      key_dir = Dir.mktmpdir('keysloth_ssh_')
      private_key_path = File.join(key_dir, 'id_rsa')
      public_key_path = File.join(key_dir, 'id_rsa.pub')

      File.write(private_key_path, private_key)
      File.chmod(0o600, private_key_path)

      if public_key
        File.write(public_key_path, public_key)
      else
        # Если публичный ключ не предоставлен, генерируем его из приватного
        public_key_path = nil
      end

      Rugged::Credentials::SshKey.new(
        username: 'git',
        publickey: public_key_path,
        privatekey: private_key_path
      )
    end

    # Создает подпись для коммита с автора информацией
    #
    # Получает имя и email автора коммита из переменных окружения Git
    # или использует значения по умолчанию для KeySloth. Поддерживает
    # как GIT_AUTHOR_* так и GIT_COMMITTER_* переменные.
    #
    # @return [Rugged::Signature] Подпись с именем, email и временной меткой
    # @example Использование с переменными окружения
    #   ENV['GIT_AUTHOR_NAME'] = 'John Doe'
    #   ENV['GIT_AUTHOR_EMAIL'] = 'john@example.com'
    #   signature = create_commit_signature
    # @example Использование значений по умолчанию
    #   signature = create_commit_signature #=> name: 'KeySloth', email: 'keysloth@example.com'
    def create_commit_signature
      name = ENV['GIT_AUTHOR_NAME'] || ENV['GIT_COMMITTER_NAME'] || 'KeySloth'
      email = ENV['GIT_AUTHOR_EMAIL'] || ENV['GIT_COMMITTER_EMAIL'] || 'keysloth@example.com'

      Rugged::Signature.new(name, email, Time.now)
    end
  end
end
