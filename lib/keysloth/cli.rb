# frozen_string_literal: true

require 'thor'

module KeySloth
  # Интерфейс командной строки для KeySloth
  #
  # Предоставляет команды pull, push и help для управления секретами.
  # Использует Thor для парсинга аргументов командной строки.
  #
  # @example Использование CLI
  #   # Получение секретов
  #   keysloth pull --repo git@github.com:company/secrets.git --password secret
  #
  #   # Отправка секретов
  #   keysloth push --repo git@github.com:company/secrets.git --password secret
  #
  #   # Справка
  #   keysloth help
  #
  # @author KeySloth Team
  # @since 0.1.0
  class CLI < Thor
    class_option :verbose, type: :boolean, aliases: '-v',
                           desc: 'Включить подробное логирование (DEBUG уровень)'
    class_option :quiet, type: :boolean, aliases: '-q',
                         desc: 'Тихий режим (только ошибки)'
    class_option :config, type: :string, aliases: '-c',
                          desc: 'Путь к файлу конфигурации .keyslothrc'

    desc 'pull', 'Получить и расшифровать секреты из Git репозитория'
    long_desc <<~DESC
      Команда pull клонирует указанный Git репозиторий, получает зашифрованные файлы
      из указанной ветки, расшифровывает их с использованием предоставленного пароля
      и сохраняет в локальную директорию.

      Поддерживаемые типы файлов секретов:
      - .cer (сертификаты)
      - .p12 (PKCS#12 сертификаты)
      - .mobileprovisioning (профили подготовки iOS)
      - .json (конфигурационные файлы)

      Перед выполнением операции автоматически создается резервная копия
      существующей локальной директории с секретами.
    DESC
    option :repo, type: :string, aliases: '-r',
                  desc: 'URL Git репозитория (SSH: git@github.com:user/repo.git)'
    option :branch, type: :string, default: 'main', aliases: '-b',
                    desc: 'Ветка репозитория для получения секретов'
    option :password, type: :string, required: true, aliases: '-p',
                      desc: 'Пароль для расшифровки секретов'
    option :path, type: :string, default: './secrets', aliases: '-d',
                  desc: 'Локальный путь для сохранения расшифрованных секретов'
    def pull
      setup_logger

      logger.info('=== Начинаем операцию получения секретов ===')

      begin
        KeySloth.pull(
          repo_url: options[:repo],
          branch: options[:branch],
          password: options[:password],
          local_path: options[:path],
          config_file: options[:config]
        )

        logger.info('=== Операция получения секретов завершена успешно ===')
      rescue KeySloth::KeySlothError => e
        logger.error("Ошибка выполнения операции: #{e.message}")
        exit 1
      end
    end

    desc 'push', 'Зашифровать и отправить секреты в Git репозиторий'
    long_desc <<~DESC
      Команда push читает файлы секретов из локальной директории, шифрует их
      с использованием предоставленного пароля и отправляет в указанный
      Git репозиторий в указанную ветку.

      Перед отправкой выполняется проверка актуальности удаленной ветки.
      При обнаружении конфликтов операция прекращается с детальным сообщением
      об ошибке.

      Поддерживаемые типы файлов секретов:
      - .cer (сертификаты)
      - .p12 (PKCS#12 сертификаты)#{' '}
      - .mobileprovisioning (профили подготовки iOS)
      - .json (конфигурационные файлы)
    DESC
    option :repo, type: :string, aliases: '-r',
                  desc: 'URL Git репозитория (SSH: git@github.com:user/repo.git)'
    option :branch, type: :string, default: 'main', aliases: '-b',
                    desc: 'Ветка репозитория для отправки секретов'
    option :password, type: :string, required: true, aliases: '-p',
                      desc: 'Пароль для шифрования секретов'
    option :path, type: :string, default: './secrets', aliases: '-d',
                  desc: 'Локальный путь с секретами для шифрования'
    option :message, type: :string, aliases: '-m',
                     desc: 'Сообщение коммита (опционально)'
    def push
      setup_logger

      logger.info('=== Начинаем операцию отправки секретов ===')

      begin
        KeySloth.push(
          repo_url: options[:repo],
          branch: options[:branch],
          password: options[:password],
          local_path: options[:path],
          config_file: options[:config],
          commit_message: options[:message]
        )

        logger.info('=== Операция отправки секретов завершена успешно ===')
      rescue KeySloth::KeySlothError => e
        logger.error("Ошибка выполнения операции: #{e.message}")
        exit 1
      end
    end

    desc 'status', 'Проверить состояние локальных секретов'
    long_desc <<~DESC
      Команда status показывает информацию о состоянии локальных секретов:
      - Количество найденных файлов секретов
      - Список файлов с их размерами
      - Информацию о доступных резервных копиях
      - Проверку целостности файлов
    DESC
    option :path, type: :string, default: './secrets', aliases: '-d',
                  desc: 'Локальный путь с секретами для проверки'
    def status
      setup_logger

      logger.info('=== Проверяем состояние локальных секретов ===')

      begin
        file_manager = FileManager.new(logger)

        unless file_manager.directory_exists?(options[:path])
          logger.warn("Директория секретов не существует: #{options[:path]}")
          return
        end

        # Собираем файлы секретов
        secret_files = file_manager.collect_secret_files(options[:path])

        if secret_files.empty?
          logger.info('Файлы секретов не найдены')
          return
        end

        logger.info("Найдено #{secret_files.size} файлов секретов:")

        secret_files.each do |file_path|
          size = File.size(file_path)
          relative_path = file_manager.get_relative_path(file_path, options[:path])
          integrity = file_manager.verify_file_integrity(file_path) ? '✓' : '✗'

          logger.info("  #{integrity} #{relative_path} (#{size} байт)")
        end

        # Показываем информацию о backup'ах
        backups = file_manager.list_backups(options[:path])
        if backups.any?
          logger.info("\nДоступные резервные копии:")
          backups.each do |backup_path|
            backup_time = File.basename(backup_path).match(/_(\d{8}_\d{6})$/)&.captures&.first
            if backup_time
              formatted_time = Time.strptime(backup_time,
                                             '%Y%m%d_%H%M%S').strftime('%Y-%m-%d %H:%M:%S')
              logger.info("  #{File.basename(backup_path)} (#{formatted_time})")
            else
              logger.info("  #{File.basename(backup_path)}")
            end
          end
        else
          logger.info("\nРезервные копии не найдены")
        end
      rescue KeySloth::KeySlothError => e
        logger.error("Ошибка проверки состояния: #{e.message}")
        exit 1
      end
    end

    desc 'restore BACKUP_PATH', 'Восстановить секреты из резервной копии'
    long_desc <<~DESC
      Команда restore восстанавливает локальные секреты из указанной
      резервной копии. Используйте команду 'status' для просмотра
      доступных резервных копий.
    DESC
    option :path, type: :string, default: './secrets', aliases: '-d',
                  desc: 'Локальный путь для восстановления секретов'
    def restore(backup_path)
      setup_logger

      logger.info('=== Восстанавливаем секреты из резервной копии ===')

      begin
        file_manager = FileManager.new(logger)
        file_manager.restore_from_backup(backup_path, options[:path])

        logger.info('=== Восстановление завершено успешно ===')
      rescue KeySloth::KeySlothError => e
        logger.error("Ошибка восстановления: #{e.message}")
        exit 1
      end
    end

    desc 'validate', 'Проверить целостность файлов секретов'
    long_desc <<~DESC
      Команда validate выполняет проверку целостности всех файлов секретов
      в указанной директории:
      - Проверяет доступность файлов для чтения
      - Проверяет что файлы не пустые
      - Валидирует структуру файлов секретов
      - Выводит детальный отчет о состоянии каждого файла
    DESC
    option :path, type: :string, default: './secrets', aliases: '-d',
                  desc: 'Локальный путь с секретами для проверки'
    def validate
      setup_logger

      logger.info('=== Проверяем целостность файлов секретов ===')

      begin
        file_manager = FileManager.new(logger)

        unless file_manager.directory_exists?(options[:path])
          logger.error("Директория секретов не существует: #{options[:path]}")
          exit 1
        end

        # Собираем файлы секретов
        secret_files = file_manager.collect_secret_files(options[:path])

        if secret_files.empty?
          logger.warn('Файлы секретов не найдены')
          return
        end

        logger.info("Проверяем #{secret_files.size} файлов секретов...")

        valid_files = 0
        invalid_files = 0

        secret_files.each do |file_path|
          relative_path = file_manager.get_relative_path(file_path, options[:path])

          if file_manager.verify_file_integrity(file_path)
            logger.info("  ✓ #{relative_path} - файл корректен")
            valid_files += 1
          else
            logger.error("  ✗ #{relative_path} - файл поврежден или недоступен")
            invalid_files += 1
          end
        end

        # Итоговый отчет
        logger.info("\n=== Результаты проверки ===")
        logger.info("Корректных файлов: #{valid_files}")
        logger.info("Поврежденных файлов: #{invalid_files}")

        if invalid_files.positive?
          logger.error("Обнаружены поврежденные файлы! Рекомендуется восстановление из backup'а.")
          exit 1
        else
          logger.info('Все файлы секретов прошли проверку целостности.')
        end
      rescue KeySloth::KeySlothError => e
        logger.error("Ошибка проверки целостности: #{e.message}")
        exit 1
      end
    end

    desc 'init', 'Инициализировать новый проект с KeySloth'
    long_desc <<~DESC
      Команда init выполняет первичную настройку KeySloth в проекте:
      - Создает файл конфигурации .keyslothrc
      - Создает локальную директорию для секретов
      - Добавляет директорию секретов в .gitignore
      - Создает примеры конфигурации

      После выполнения команды можно использовать pull и push для работы с секретами.
    DESC
    option :repo, type: :string, required: true, aliases: '-r',
                  desc: 'URL Git репозитория для хранения секретов'
    option :branch, type: :string, default: 'main', aliases: '-b',
                    desc: 'Ветка репозитория для секретов'
    option :path, type: :string, default: './secrets', aliases: '-d',
                  desc: 'Локальный путь для секретов'
    option :force, type: :boolean, aliases: '-f',
                   desc: 'Перезаписать существующие файлы конфигурации'
    def init
      setup_logger

      logger.info('=== Инициализируем KeySloth проект ===')

      begin
        file_manager = FileManager.new(logger)

        config_path = '.keyslothrc'
        gitignore_path = '.gitignore'
        secrets_path = options[:path]

        # Проверяем существование конфигурации
        if File.exist?(config_path) && !options[:force]
          logger.error("Файл #{config_path} уже существует. Используйте --force для перезаписи.")
          exit 1
        end

        # Создаем конфигурационный файл
        config_content = <<~YAML
          # Конфигурация KeySloth
          repo_url: "#{options[:repo]}"
          branch: "#{options[:branch]}"
          local_path: "#{secrets_path}"
          backup_count: 3
        YAML

        File.write(config_path, config_content)
        logger.info("Создан файл конфигурации: #{config_path}")

        # Создаем директорию для секретов
        file_manager.ensure_directory(secrets_path)
        logger.info("Создана директория для секретов: #{secrets_path}")

        # Обновляем .gitignore
        gitignore_entry = "\n# KeySloth секреты\n#{secrets_path}/\n.keyslothrc\n"

        if File.exist?(gitignore_path)
          gitignore_content = File.read(gitignore_path)
          if gitignore_content.include?(secrets_path)
            logger.info('Файл .gitignore уже содержит правила для KeySloth')
          else
            File.write(gitignore_path, gitignore_content + gitignore_entry)
            logger.info('Обновлен файл .gitignore')
          end
        else
          File.write(gitignore_path, gitignore_entry.strip)
          logger.info('Создан файл .gitignore')
        end

        # Создаем README для директории секретов
        readme_path = File.join(secrets_path, 'README.md')
        readme_content = <<~MARKDOWN
          # Секреты проекта

          Эта директория содержит зашифрованные секреты проекта, управляемые KeySloth.

          ## Использование

          ### Получение секретов
          ```bash
          keysloth pull
          ```

          ### Отправка секретов
          ```bash
          keysloth push
          ```

          ### Проверка состояния
          ```bash
          keysloth status
          ```

          ## Поддерживаемые типы файлов
          - `.cer` - сертификаты
          - `.p12` - PKCS#12 сертификаты
          - `.mobileprovisioning` - профили подготовки iOS
          - `.json` - конфигурационные файлы

          **ВНИМАНИЕ:** Никогда не коммитьте эту директорию в Git!
        MARKDOWN

        File.write(readme_path, readme_content)
        logger.info("Создан файл справки: #{readme_path}")

        logger.info("\n=== Инициализация завершена успешно ===")
        logger.info('Следующие шаги:')
        logger.info("1. Поместите ваши файлы секретов в #{secrets_path}/")
        logger.info("2. Используйте 'keysloth push' для первой отправки секретов")
        logger.info('3. Поделитесь паролем шифрования с командой')
      rescue KeySloth::KeySlothError => e
        logger.error("Ошибка инициализации: #{e.message}")
        exit 1
      rescue StandardError => e
        logger.error("Неожиданная ошибка: #{e.message}")
        exit 1
      end
    end

    desc 'version', 'Показать версию KeySloth'
    def version
      puts "KeySloth версия #{KeySloth::VERSION}"
    end

    # Переопределяем help для улучшенного вывода
    desc 'help [COMMAND]', 'Показать справку по командам'
    def help(command = nil)
      if command
        super
      else
        puts <<~HELP
          KeySloth v#{KeySloth::VERSION} - Управление зашифрованными секретами в Git репозиториях

          ИСПОЛЬЗОВАНИЕ:
            keysloth COMMAND [OPTIONS]

          КОМАНДЫ:
            init     Инициализировать новый проект с KeySloth
            pull     Получить и расшифровать секреты из Git репозитория
            push     Зашифровать и отправить секреты в Git репозиторий#{'  '}
            status   Проверить состояние локальных секретов
            validate Проверить целостность файлов секретов
            restore  Восстановить секреты из резервной копии
            version  Показать версию KeySloth
            help     Показать эту справку

          ГЛОБАЛЬНЫЕ ОПЦИИ:
            -v, --verbose    Подробное логирование (DEBUG уровень)
            -q, --quiet      Тихий режим (только ошибки)
            -c, --config     Путь к файлу конфигурации .keyslothrc

          ПРИМЕРЫ:
            # Инициализировать новый проект
            keysloth init -r git@github.com:company/secrets.git

            # Получить секреты из репозитория
            keysloth pull -r git@github.com:company/secrets.git -p mypassword

            # Отправить секреты в репозиторий
            keysloth push -r git@github.com:company/secrets.git -p mypassword -m "Update certificates"

            # Проверить состояние и целостность
            keysloth status
            keysloth validate

          Для подробной справки по команде используйте: keysloth help COMMAND
        HELP
      end
    end

    private

    # Настраивает логгер в соответствии с параметрами командной строки
    def setup_logger
      level = if options[:verbose]
                :debug
              elsif options[:quiet]
                :error
              else
                :info
              end

      @logger = Logger.new(level: level)
    end

    # Возвращает настроенный логгер
    #
    # @return [KeySloth::Logger] Настроенный логгер
    def logger
      @logger ||= Logger.new
    end
  end
end
