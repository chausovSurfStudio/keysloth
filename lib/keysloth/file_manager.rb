# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module KeySloth
  # Класс для управления файловыми операциями KeySloth
  #
  # Обеспечивает создание директорий, чтение и запись файлов,
  # создание резервных копий и валидацию путей.
  # Поддерживает работу с различными типами секретных файлов.
  #
  # @example Использование
  #   file_manager = KeySloth::FileManager.new
  #
  #   # Создание директории
  #   file_manager.ensure_directory('./secrets')
  #
  #   # Сбор файлов секретов
  #   files = file_manager.collect_secret_files('./secrets')
  #
  #   # Создание backup'а
  #   file_manager.create_backup('./secrets')
  #
  # @author KeySloth Team
  # @since 0.1.0
  class FileManager

    # Максимальное количество backup'ов
    DEFAULT_BACKUP_COUNT = 3

    # Инициализация файлового менеджера
    #
    # @param logger [KeySloth::Logger] Логгер для вывода сообщений
    # @param backup_count [Integer] Количество backup'ов для хранения
    def initialize(logger = nil, backup_count = DEFAULT_BACKUP_COUNT)
      @logger = logger || Logger.new(level: :error)
      @backup_count = backup_count
    end

    # Обеспечивает существование директории
    #
    # @param path [String] Путь к директории
    # @raise [FileSystemError] при ошибках создания директории
    def ensure_directory(path)
      return if directory_exists?(path)

      @logger.info("Создаем директорию: #{path}")

      begin
        FileUtils.mkdir_p(path)
        @logger.debug("Директория успешно создана: #{path}")
      rescue StandardError => e
        @logger.error('Ошибка создания директории', e)
        raise FileSystemError, "Не удалось создать директорию #{path}: #{e.message}"
      end
    end

    # Проверяет существование директории
    #
    # @param path [String] Путь к директории
    # @return [Boolean] true если директория существует
    def directory_exists?(path)
      File.directory?(path)
    end

    # Читает содержимое файла
    #
    # @param file_path [String] Путь к файлу
    # @return [String] Содержимое файла
    # @raise [FileSystemError] при ошибках чтения файла
    def read_file(file_path)
      @logger.debug("Читаем файл: #{file_path}")

      begin
        content = File.binread(file_path)
        @logger.debug("Файл прочитан успешно (размер: #{content.length} байт)")
        content
      rescue StandardError => e
        @logger.error('Ошибка чтения файла', e)
        raise FileSystemError, "Не удалось прочитать файл #{file_path}: #{e.message}"
      end
    end

    # Записывает содержимое в файл
    #
    # @param file_path [String] Путь к файлу
    # @param content [String] Содержимое для записи
    # @raise [FileSystemError] при ошибках записи файла
    def write_file(file_path, content)
      @logger.debug("Записываем файл: #{file_path}")

      begin
        # Создаем директорию если не существует
        directory = File.dirname(file_path)
        ensure_directory(directory) unless directory_exists?(directory)

        File.binwrite(file_path, content)
        @logger.debug("Файл записан успешно (размер: #{content.length} байт)")
      rescue StandardError => e
        @logger.error('Ошибка записи файла', e)
        raise FileSystemError, "Не удалось записать файл #{file_path}: #{e.message}"
      end
    end

    # Собирает все файлы секретов из директории (wildcard)
    #
    # Рекурсивно собирает любые обычные файлы, исключая:
    # - .enc файлы (они являются артефактами репозитория)
    # - содержимое .git директорий
    # - общеизвестные мусорные файлы (.DS_Store, Thumbs.db)
    # - локальный README.md внутри каталога секретов
    #
    # @param directory_path [String] Путь к директории с секретами
    # @return [Array<String>] Массив путей к файлам секретов
    # @raise [FileSystemError] при ошибках доступа к директории
    def collect_secret_files(directory_path)
      @logger.debug("Собираем файлы секретов из: #{directory_path}")

      begin
        validate_directory_access!(directory_path)

        all_candidates = Dir.glob(File.join(directory_path, '**', '*'), File::FNM_DOTMATCH)

        files = all_candidates.select do |path|
          next false unless File.file?(path)

          relative = get_relative_path(path, directory_path)

          # Исключаем .git содержимое
          next false if relative.split(File::SEPARATOR).include?('.git')

          # Исключаем артефакты шифрования
          next false if File.extname(path).downcase == '.enc'

          # Исключаем общеизвестный мусор и локальный README.md
          base = File.basename(path)
          next false if base == '.DS_Store' || base == 'Thumbs.db' || base == 'README.md'

          true
        end

        @logger.info("Найдено #{files.size} файлов секретов")
        files.sort
      rescue StandardError => e
        @logger.error('Ошибка сбора файлов секретов', e)
        raise FileSystemError, "Не удалось собрать файлы секретов: #{e.message}"
      end
    end

    # Возвращает относительный путь файла
    #
    # @param file_path [String] Полный путь к файлу
    # @param base_path [String] Базовый путь
    # @return [String] Относительный путь
    def get_relative_path(file_path, base_path)
      Pathname.new(file_path).relative_path_from(Pathname.new(base_path)).to_s
    end

    # Создает резервную копию директории
    #
    # @param directory_path [String] Путь к директории для backup'а
    # @return [String, nil] Путь к созданному backup'у или nil если директория не существует
    # @raise [FileSystemError] при ошибках создания backup'а
    def create_backup(directory_path)
      return nil unless directory_exists?(directory_path)
      # Отключение бэкапов: при нулевом или отрицательном лимите
      return nil if @backup_count.to_i <= 0

      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      backup_name = "#{File.basename(directory_path)}_backup_#{timestamp}"
      backup_path = File.join(File.dirname(directory_path), backup_name)

      @logger.info("Создаем backup: #{backup_path}")

      begin
        FileUtils.cp_r(directory_path, backup_path)

        # Очищаем старые backup'ы
        cleanup_old_backups(File.dirname(directory_path), File.basename(directory_path))

        @logger.debug("Backup успешно создан: #{backup_path}")
        backup_path
      rescue StandardError => e
        @logger.error('Ошибка создания backup', e)
        raise FileSystemError, "Не удалось создать backup #{directory_path}: #{e.message}"
      end
    end

    # Восстанавливает из backup'а
    #
    # @param backup_path [String] Путь к backup'у
    # @param target_path [String] Путь для восстановления
    # @raise [FileSystemError] при ошибках восстановления
    def restore_from_backup(backup_path, target_path)
      @logger.info("Восстанавливаем из backup: #{backup_path}")

      begin
        validate_backup_path!(backup_path)

        # Удаляем существующую директорию
        FileUtils.rm_rf(target_path)

        # Копируем из backup'а
        FileUtils.cp_r(backup_path, target_path)

        @logger.info('Восстановление из backup завершено')
      rescue StandardError => e
        @logger.error('Ошибка восстановления из backup', e)
        raise FileSystemError, "Не удалось восстановить из backup: #{e.message}"
      end
    end

    # Возвращает список доступных backup'ов
    #
    # @param directory_path [String] Путь к директории
    # @return [Array<String>] Массив путей к backup'ам (отсортированный по времени)
    def list_backups(directory_path)
      base_name = File.basename(directory_path)
      parent_dir = File.dirname(directory_path)
      backup_pattern = File.join(parent_dir, "#{base_name}_backup_*")

      Dir.glob(backup_pattern)
        .select { |path| File.directory?(path) }
        .sort
        .reverse # Новые backup'ы первыми
    end

    # Проверяет целостность файла секрета
    #
    # @param file_path [String] Путь к файлу
    # @return [Boolean] true если файл прошел проверку целостности
    def verify_file_integrity(file_path)
      return false unless File.exist?(file_path)
      return false if File.empty?(file_path)

      # Базовая проверка на читаемость
      begin
        content = File.binread(file_path, 100) # Читаем первые 100 байт для проверки

        # Дополнительная проверка по типу файла
        file_extension = File.extname(file_path).downcase
        verify_file_type_integrity(content, file_extension)
      rescue StandardError => e
        @logger.debug("Ошибка проверки целостности файла #{file_path}: #{e.message}")
        false
      end
    end

    # Выполняет детальную проверку целостности файла
    #
    # @param file_path [String] Путь к файлу
    # @return [Hash] Детальный результат проверки
    def verify_file_integrity_detailed(file_path)
      result = {
        valid: false,
        exists: false,
        readable: false,
        non_empty: false,
        type_valid: false,
        size: 0,
        error: nil
      }

      begin
        # Проверяем существование
        result[:exists] = File.exist?(file_path)
        return result unless result[:exists]

        # Проверяем размер
        result[:size] = File.size(file_path)
        result[:non_empty] = result[:size].positive?
        return result unless result[:non_empty]

        # Проверяем читаемость
        content = File.binread(file_path, 200) # Читаем больше для детальной проверки
        result[:readable] = true

        # Проверяем соответствие типу файла
        file_extension = File.extname(file_path).downcase
        result[:type_valid] = verify_file_type_integrity(content, file_extension)

        result[:valid] = result[:exists] && result[:readable] &&
                         result[:non_empty] && result[:type_valid]

        @logger.debug("Детальная проверка файла #{file_path}: #{result}")
      rescue StandardError => e
        result[:error] = e.message
        @logger.debug("Ошибка детальной проверки файла #{file_path}: #{e.message}")
      end

      result
    end

    # Валидирует путь файла
    #
    # @param file_path [String] Путь к файлу
    # @raise [ValidationError] при некорректном пути
    def validate_file_path!(file_path)
      if file_path.nil? || file_path.empty?
        raise ValidationError, 'Путь к файлу не может быть пустым'
      end

      # Проверяем на потенциально опасные пути
      normalized_path = File.expand_path(file_path)
      if normalized_path.include?('..')
        raise ValidationError, 'Путь содержит потенциально опасные элементы'
      end
    end

    private

    # Валидирует доступ к директории
    #
    # @param directory_path [String] Путь к директории
    # @raise [FileSystemError] при проблемах доступа
    def validate_directory_access!(directory_path)
      unless directory_exists?(directory_path)
        raise FileSystemError, "Директория не существует: #{directory_path}"
      end

      unless File.readable?(directory_path)
        raise FileSystemError, "Директория не доступна для чтения: #{directory_path}"
      end
    end

    # Валидирует путь к backup'у
    #
    # @param backup_path [String] Путь к backup'у
    # @raise [FileSystemError] при некорректном backup'е
    def validate_backup_path!(backup_path)
      raise FileSystemError, "Backup не существует: #{backup_path}" unless File.exist?(backup_path)

      unless File.directory?(backup_path)
        raise FileSystemError, "Backup не является директорией: #{backup_path}"
      end
    end

    # Очищает старые backup'ы
    #
    # @param parent_dir [String] Родительская директория
    # @param base_name [String] Базовое имя директории
    def cleanup_old_backups(parent_dir, base_name)
      # При отключённых бэкапах не удаляем существующие
      return if @backup_count.to_i <= 0

      backups = list_backups(File.join(parent_dir, base_name))

      return if backups.size <= @backup_count

      # Удаляем старые backup'ы, оставляя только нужное количество
      backups.drop(@backup_count).each do |old_backup|
        @logger.debug("Удаляем старый backup: #{old_backup}")
        FileUtils.remove_entry(old_backup)
      end
    end

    # Проверяет целостность файла по его типу
    #
    # @param content [String] Содержимое файла (первые байты)
    # @param file_extension [String] Расширение файла
    # @return [Boolean] true если файл соответствует ожидаемому формату
    def verify_file_type_integrity(content, file_extension)
      return false if content.nil? || content.empty?

      case file_extension
      when '.cer'
        # Проверяем сертификат (.cer файлы)
        verify_certificate_format(content)
      when '.p12'
        # Проверяем PKCS#12 файлы
        verify_p12_format(content)
      when '.mobileprovisioning'
        # Проверяем файлы mobile provisioning
        verify_mobileprovisioning_format(content)
      when '.json'
        # Проверяем JSON файлы
        verify_json_format(content)
      else
        # Для неизвестных типов - только базовая проверка
        @logger.debug("Неизвестный тип файла: #{file_extension}")
        true
      end
    end

    # Проверяет формат сертификата (.cer файлы)
    #
    # Поддерживает проверку PEM и DER форматов сертификатов.
    # PEM формат содержит текстовые маркеры BEGIN/END CERTIFICATE.
    # DER формат - бинарный ASN.1, начинается с SEQUENCE tag (0x30).
    #
    # @param content [String] Содержимое файла сертификата
    # @return [Boolean] true если формат корректен
    # @example Проверка PEM сертификата
    #   content = "-----BEGIN CERTIFICATE-----\nMIIC..."
    #   verify_certificate_format(content) #=> true
    def verify_certificate_format(content)
      # PEM формат
      return true if content.include?('-----BEGIN CERTIFICATE-----')

      # DER формат (бинарный) - проверяем первые байты
      # DER сертификаты начинаются с 0x30 (SEQUENCE tag)
      return true if content.bytes.first == 0x30

      @logger.debug('Файл не соответствует формату сертификата')
      false
    end

    # Проверяет формат PKCS#12 (.p12 файлы)
    #
    # PKCS#12 - стандарт для хранения криптографических объектов
    # (сертификаты + приватные ключи). Использует ASN.1 DER кодирование,
    # поэтому файл должен начинаться с SEQUENCE tag (0x30).
    #
    # @param content [String] Содержимое файла PKCS#12
    # @return [Boolean] true если формат корректен
    # @raise [FileSystemError] при невозможности прочитать файл
    def verify_p12_format(content)
      # PKCS#12 файлы начинаются с 0x30 (SEQUENCE tag)
      return true if content.bytes.first == 0x30

      @logger.debug('Файл не соответствует формату PKCS#12')
      false
    end

    # Проверяет формат Mobile Provisioning Profile (.mobileprovisioning файлы)
    #
    # Профили подготовки iOS могут быть в XML (текстовом) или бинарном plist формате.
    # XML профили содержат стандартные XML/plist маркеры.
    # Бинарные профили начинаются с 'bplist' сигнатуры.
    #
    # @param content [String] Содержимое файла профиля
    # @return [Boolean] true если формат корректен
    # @example Проверка XML профиля
    #   content = "<?xml version=\"1.0\"..."
    #   verify_mobileprovisioning_format(content) #=> true
    def verify_mobileprovisioning_format(content)
      # Mobile provisioning файлы содержат XML или plist структуру
      return true if content.include?('<?xml') || content.include?('<plist')

      # Могут быть в бинарном plist формате
      return true if content.include?('bplist')

      @logger.debug('Файл не соответствует формату mobile provisioning')
      false
    end

    # Проверяет формат JSON (.json файлы)
    #
    # Выполняет базовую структурную проверку JSON документов.
    # Проверяет наличие открывающих и закрывающих скобок для объектов {}
    # и массивов []. Не выполняет полную JSON валидацию для производительности.
    #
    # @param content [String] Содержимое JSON файла
    # @return [Boolean] true если базовая структура корректна
    # @example Проверка JSON объекта
    #   content = '{"key": "value"}'
    #   verify_json_format(content) #=> true
    # @example Проверка JSON массива
    #   content = '[{"item": 1}]'
    #   verify_json_format(content) #=> true
    def verify_json_format(content)
      # Базовая проверка JSON структуры
      trimmed = content.strip
      return true if (trimmed.start_with?('{') && trimmed.include?('}')) ||
                     (trimmed.start_with?('[') && trimmed.include?(']'))

      @logger.debug('Файл не соответствует формату JSON')
      false
    end
  end
end
