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
      @ssh_tmp_dir = nil
      @git_env = {}

      validate_repo_url!
      check_git_available!
      prepare_git_environment
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
        ensure_branch_up_to_date(branch)

        files = collect_encrypted_files
        @logger.info("Найдено #{files.size} зашифрованных файлов")

        files
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
        ensure_branch_up_to_date(branch)
      rescue StandardError => e
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
        add_all_changes

        unless has_changes?
          @logger.info('Нет изменений для коммита')
          return
        end

        ensure_git_user_config!
        create_commit(commit_message)
        push_to_remote(branch)

        @logger.info('Изменения успешно отправлены в репозиторий')
      rescue StandardError => e
        @logger.error('Ошибка коммита или отправки', e)
        raise RepositoryError, "Не удалось отправить изменения: #{e.message}"
      end
    end

    # Очищает временные файлы
    def cleanup
      if @temp_dir && Dir.exist?(@temp_dir)
        @logger.debug("Очищаем временную директорию: #{@temp_dir}")
        FileUtils.remove_entry(@temp_dir)
        @temp_dir = nil
      end

      if @ssh_tmp_dir && Dir.exist?(@ssh_tmp_dir)
        @logger.debug("Очищаем временные SSH ключи: #{@ssh_tmp_dir}")
        FileUtils.remove_entry(@ssh_tmp_dir)
        @ssh_tmp_dir = nil
      end
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

    # Настраивает окружение Git и SSH
    def prepare_git_environment
      ssh_command = build_ssh_command
      @git_env = {}
      @git_env['GIT_SSH_COMMAND'] = ssh_command if ssh_command
    end

    # Клонирует репозиторий во временную директорию
    #
    # @raise [RepositoryError] при ошибках клонирования
    def clone_repository
      return if @temp_dir

      @temp_dir = Dir.mktmpdir('keysloth_repo_')
      @logger.debug("Создана временная директория: #{@temp_dir}")

      depth_flag = ENV['KEYSLOTH_FULL_CLONE'].to_s.downcase == 'true' ? [] : ['--depth', '1']
      cmd = ['git', 'clone', '--quiet'] + depth_flag + [@repo_url, @temp_dir]
      run_git(cmd)

      @logger.debug('Репозиторий успешно клонирован')
    end

    # Переключается на указанную ветку
    #
    # @param branch [String] Имя ветки
    # @raise [RepositoryError] при ошибках переключения ветки
    def checkout_branch(branch)
      @logger.debug("Переключаемся на ветку: #{branch}")

      # Проверяем, существует ли локальная ветка
      stdout, = run_git(['git', 'rev-parse', '--verify', branch], chdir: @temp_dir,
                                                                  allow_failure: true)
      if stdout && !stdout.strip.empty?
        run_git(['git', 'checkout', branch], chdir: @temp_dir)
        @logger.debug("Успешно переключились на ветку: #{branch}")
        return
      end

      # Пробуем создать локальную ветку, отслеживающую origin/<branch>
      _, stderr, status = Open3.capture3(@git_env, 'git', 'checkout', '-b', branch, '--track',
                                         "origin/#{branch}", chdir: @temp_dir)
      if status.success?
        @logger.debug("Создана и выбрана новая ветка: #{branch}")
        return
      end

      raise RepositoryError, "Ветка '#{branch}' не найдена в репозитории: #{stderr.strip}"
    end

    # Проверяет актуальность локальной ветки
    #
    # @param branch [String] Имя ветки
    # @raise [RepositoryError] если ветка не актуальна
    def ensure_branch_up_to_date(branch)
      run_git(['git', 'fetch', 'origin', branch], chdir: @temp_dir)

      # Пытаемся fast-forward pull
      _, _, status = Open3.capture3(@git_env, 'git', 'pull', '--ff-only', 'origin', branch,
                                    chdir: @temp_dir)
      return if status.success?

      # Если shallow-история мешает, пробуем развернуть историю
      @logger.debug('Повторная попытка pull после развертывания истории (unshallow)')
      _, _, fetch_status = Open3.capture3(@git_env, 'git', 'fetch', '--unshallow', chdir: @temp_dir)
      if fetch_status.success?
        out2, err2, st2 = Open3.capture3(@git_env, 'git', 'pull', '--ff-only', 'origin', branch,
                                         chdir: @temp_dir)
        return if st2.success?

        raise RepositoryError,
              "Не удалось обновить ветку fast-forward: #{(err2.empty? ? out2 : err2).strip}"
      end

      raise RepositoryError, 'Не удалось выполнить git pull --ff-only'
    end

    # Собирает все зашифрованные файлы из репозитория
    #
    # @return [Array<Hash>] Массив данных файлов
    def collect_encrypted_files
      files = []

      Dir.glob('**/*.enc', base: @temp_dir).sort.each do |relative_path|
        full_path = File.join(@temp_dir, relative_path)
        next unless File.file?(full_path)

        files << {
          name: relative_path,
          content: File.read(full_path)
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
      run_git(['git', 'add', '-A'], chdir: @temp_dir)
    end

    # Проверяет наличие изменений
    #
    # @return [Boolean] true если есть изменения
    def has_changes?
      stdout, = run_git(['git', 'status', '--porcelain'], chdir: @temp_dir)
      !stdout.strip.empty?
    end

    # Создает коммит
    #
    # @param message [String] Сообщение коммита
    def create_commit(message)
      run_git(['git', 'commit', '-m', message], chdir: @temp_dir)
      @logger.debug("Создан коммит: #{message}")
    end

    # Отправляет изменения в удаленный репозиторий
    #
    # @param branch [String] Имя ветки
    def push_to_remote(branch)
      run_git(['git', 'push', 'origin', branch], chdir: @temp_dir)
      @logger.debug("Изменения отправлены в origin/#{branch}")
    end

    # Формирует команду SSH для GIT_SSH_COMMAND в зависимости от окружения
    #
    # Приоритет источников ключей: KEYSLOTH_SSH_KEY_PATH → SSH_PRIVATE_KEY/SSH_PUBLIC_KEY → системные ключи
    # Возвращает nil, если следует использовать системный SSH без явного указания ключа
    def build_ssh_command
      explicit_key_path = ENV.fetch('KEYSLOTH_SSH_KEY_PATH', nil)
      if explicit_key_path && !explicit_key_path.empty?
        return %(ssh -i #{explicit_key_path} -o IdentitiesOnly=yes)
      end

      if ENV['SSH_PRIVATE_KEY']
        @ssh_tmp_dir = Dir.mktmpdir('keysloth_ssh_')
        private_key_path = File.join(@ssh_tmp_dir, 'id_rsa')
        public_key_path = File.join(@ssh_tmp_dir, 'id_rsa.pub')

        File.write(private_key_path, ENV['SSH_PRIVATE_KEY'])
        File.chmod(0o600, private_key_path)
        File.write(public_key_path, ENV['SSH_PUBLIC_KEY']) if ENV['SSH_PUBLIC_KEY']

        # В CI отключаем проверку хостов (опционально)
        return %(ssh -i #{private_key_path} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
      end

      # Системные ключи/ssh-agent — используем настройки по умолчанию
      nil
    end

    # Проверяет, что git настроен с именем и email автора коммита
    def ensure_git_user_config!
      name_out, = run_git(['git', 'config', '--get', 'user.name'], chdir: @temp_dir,
                                                                   allow_failure: true)
      email_out, = run_git(['git', 'config', '--get', 'user.email'], chdir: @temp_dir,
                                                                     allow_failure: true)

      if name_out.to_s.strip.empty? || email_out.to_s.strip.empty?
        raise RepositoryError,
              'Требуются глобальные настройки Git: user.name и user.email. ' \
              'Настройте их командой: git config --global user.name "Your Name"; ' \
              'git config --global user.email "you@example.com"'
      end
    end

    # Унифицированный запуск git-команд с логированием и обработкой ошибок
    # Возвращает [stdout, stderr]
    def run_git(cmd, chdir: nil, allow_failure: false)
      start_msg = cmd.is_a?(Array) ? cmd.join(' ') : cmd.to_s
      @logger.debug("Выполняем команду: #{start_msg}")

      stdout, stderr, status = if cmd.is_a?(Array)
                                 Open3.capture3(@git_env, *cmd, chdir: chdir)
                               else
                                 Open3.capture3(@git_env, cmd, chdir: chdir)
                               end

      return [stdout, stderr] if status.success?

      exit_code = status.respond_to?(:exitstatus) ? status.exitstatus : 'unknown'
      @logger.debug("Код выхода: #{exit_code}\nSTDERR: #{stderr.strip}")
      return [stdout, stderr] if allow_failure

      base_msg = (stderr.strip.empty? ? stdout.strip : stderr.strip)
      advice = 'Совет: проверьте доступ к репозиторию, корректность ветки и SSH-настройки.'
      raise RepositoryError, [base_msg, advice].reject(&:empty?).join("\n")
    end

    # Метод сохранен для обратной совместимости интерфейса (не используется)
    def create_commit_signature
      # Используем конфигурацию git, поэтому сигнатура не формируется вручную
      nil
    end
  end
end
