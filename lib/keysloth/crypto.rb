# frozen_string_literal: true

require 'openssl'
require 'base64'

module KeySloth
  # Модуль для криптографических операций KeySloth
  #
  # Реализует шифрование и дешифрование файлов с использованием AES-256-GCM.
  # Обеспечивает защиту целостности данных и аутентификацию.
  # Использует PBKDF2 для генерации ключей из паролей.
  #
  # @example Использование
  #   crypto = KeySloth::Crypto.new('secret_password')
  #
  #   # Шифрование файла
  #   encrypted = crypto.encrypt_file(file_content)
  #
  #   # Дешифрование файла
  #   decrypted = crypto.decrypt_file(encrypted)
  #
  # @author KeySloth Team
  # @since 0.1.0
  class Crypto
    # Алгоритм шифрования
    CIPHER_ALGORITHM = 'aes-256-gcm'

    # Длина ключа в байтах (256 бит)
    KEY_LENGTH = 32

    # Длина инициализационного вектора для GCM
    IV_LENGTH = 12

    # Длина соли для PBKDF2
    SALT_LENGTH = 32

    # Количество итераций для PBKDF2
    PBKDF2_ITERATIONS = 100_000

    # Длина authentication tag для GCM
    AUTH_TAG_LENGTH = 16

    # Инициализация криптографического модуля
    #
    # @param password [String] Пароль для шифрования/дешифрования
    # @param logger [KeySloth::Logger] Логгер для вывода сообщений
    # @raise [CryptoError] при некорректном пароле
    def initialize(password, logger = nil)
      @password = password&.to_s
      @logger = logger || Logger.new(level: :error)

      validate_password!
    end

    # Шифрует содержимое файла
    #
    # @param content [String] Содержимое файла для шифрования
    # @return [String] Зашифрованный контент в формате Base64
    # @raise [CryptoError] при ошибках шифрования
    def encrypt_file(content)
      @logger.debug('Начинаем шифрование файла')

      begin
        # Обрабатываем пустой контент
        content_to_encrypt = content.to_s
        # Добавляем пробел для пустого контента
        content_to_encrypt = ' ' if content_to_encrypt.empty?

        # Генерируем случайную соль и IV
        salt = generate_random_bytes(SALT_LENGTH)
        iv = generate_random_bytes(IV_LENGTH)

        # Выводим ключ из пароля
        key = derive_key(@password, salt)

        # Создаем cipher для шифрования
        cipher = OpenSSL::Cipher.new(CIPHER_ALGORITHM)
        cipher.encrypt
        cipher.key = key
        cipher.iv = iv

        # Шифруем данные
        encrypted_data = cipher.update(content_to_encrypt) + cipher.final
        auth_tag = cipher.auth_tag

        # Упаковываем все компоненты в единый блок
        packed_data = pack_encrypted_data(salt, iv, auth_tag, encrypted_data)

        @logger.debug("Файл успешно зашифрован (размер: #{encrypted_data.length} байт)")
        Base64.strict_encode64(packed_data)
      rescue StandardError => e
        @logger.error('Ошибка при шифровании файла', e)
        raise CryptoError, "Не удалось зашифровать файл: #{e.message}"
      end
    end

    # Дешифрует содержимое файла
    #
    # @param encrypted_content [String] Зашифрованный контент в формате Base64
    # @return [String] Расшифрованное содержимое файла
    # @raise [CryptoError] при ошибках дешифрования
    def decrypt_file(encrypted_content)
      @logger.debug('Начинаем дешифрование файла')

      begin
        # Декодируем из Base64
        packed_data = Base64.strict_decode64(encrypted_content.to_s)

        # Распаковываем компоненты
        salt, iv, auth_tag, encrypted_data = unpack_encrypted_data(packed_data)

        # Выводим ключ из пароля
        key = derive_key(@password, salt)

        # Создаем cipher для дешифрования
        cipher = OpenSSL::Cipher.new(CIPHER_ALGORITHM)
        cipher.decrypt
        cipher.key = key
        cipher.iv = iv
        cipher.auth_tag = auth_tag

        # Дешифруем данные
        decrypted_data = cipher.update(encrypted_data) + cipher.final

        @logger.debug("Файл успешно расшифрован (размер: #{decrypted_data.length} байт)")
        decrypted_data
      rescue OpenSSL::Cipher::CipherError => e
        @logger.error('Ошибка дешифрования - возможно неверный пароль', e)
        raise CryptoError, 'Неверный пароль или поврежденные данные'
      rescue StandardError => e
        @logger.error('Ошибка при дешифровании файла', e)
        raise CryptoError, "Не удалось расшифровать файл: #{e.message}"
      end
    end

    # Проверяет целостность зашифрованного файла
    #
    # @param encrypted_content [String] Зашифрованный контент для проверки
    # @return [Boolean] true если файл не поврежден
    def verify_integrity(encrypted_content)
      @logger.debug('Проверяем целостность зашифрованного файла')

      begin
        # Проверяем что контент не пустой
        return false if encrypted_content.nil? || encrypted_content.empty?

        # Декодируем из Base64
        packed_data = Base64.strict_decode64(encrypted_content.to_s)

        # Проверяем минимальный размер данных
        min_size = 4 + SALT_LENGTH + 4 + IV_LENGTH + 4 + AUTH_TAG_LENGTH + 1
        return false if packed_data.length < min_size

        # Распаковываем и проверяем структуру данных
        salt, iv, auth_tag, encrypted_data = unpack_encrypted_data(packed_data)

        # Проверяем что все компоненты присутствуют
        return false if salt.nil? || iv.nil? || auth_tag.nil? || encrypted_data.nil?
        return false if salt.length != SALT_LENGTH
        return false if iv.length != IV_LENGTH
        return false if auth_tag.length != AUTH_TAG_LENGTH
        return false if encrypted_data.empty?

        @logger.debug('Файл прошел проверку целостности')
        true
      rescue StandardError => e
        @logger.debug("Ошибка проверки целостности: #{e.message}")
        false
      end
    end

    # Выполняет полную проверку целостности с проверкой расшифровки
    #
    # @param encrypted_content [String] Зашифрованный контент для проверки
    # @return [Hash] Результат проверки с деталями
    def verify_integrity_detailed(encrypted_content)
      @logger.debug('Выполняем детальную проверку целостности')

      result = {
        valid: false,
        structure_valid: false,
        decryption_valid: false,
        error: nil
      }

      begin
        # Проверяем структуру
        result[:structure_valid] = verify_integrity(encrypted_content)
        return result unless result[:structure_valid]

        # Проверяем возможность расшифровки (полная проверка)
        begin
          decrypt_file(encrypted_content)
          result[:decryption_valid] = true
        rescue CryptoError
          result[:decryption_valid] = false
        end

        result[:valid] = result[:structure_valid] && result[:decryption_valid]
        @logger.debug("Детальная проверка завершена: #{result}")
      rescue OpenSSL::Cipher::CipherError => e
        result[:error] = 'Неверный пароль или поврежденные данные'
        @logger.debug("Ошибка расшифровки при проверке: #{e.message}")
      rescue StandardError => e
        result[:error] = e.message
        @logger.debug("Ошибка детальной проверки: #{e.message}")
      end

      result
    end

    private

    # Валидирует пароль
    #
    # @raise [CryptoError] при некорректном пароле
    def validate_password!
      raise CryptoError, 'Пароль не может быть пустым' if @password.nil? || @password.empty?

      raise CryptoError, 'Пароль должен содержать минимум 8 символов' if @password.length < 8
    end

    # Генерирует случайные байты
    #
    # @param length [Integer] Количество байт
    # @return [String] Случайные байты
    def generate_random_bytes(length)
      OpenSSL::Random.random_bytes(length)
    end

    # Выводит ключ из пароля с использованием PBKDF2
    #
    # @param password [String] Пароль
    # @param salt [String] Соль
    # @return [String] Выведенный ключ
    def derive_key(password, salt)
      OpenSSL::PKCS5.pbkdf2_hmac(
        password,
        salt,
        PBKDF2_ITERATIONS,
        KEY_LENGTH,
        OpenSSL::Digest.new('SHA256')
      )
    end

    # Упаковывает зашифрованные данные в единый блок
    #
    # @param salt [String] Соль
    # @param iv [String] Инициализационный вектор
    # @param auth_tag [String] Authentication tag
    # @param encrypted_data [String] Зашифрованные данные
    # @return [String] Упакованные данные
    def pack_encrypted_data(salt, iv, auth_tag, encrypted_data)
      # Формат: [длина_соли][соль][длина_iv][iv][длина_auth_tag][auth_tag][зашифрованные_данные]
      [
        SALT_LENGTH,
        salt,
        IV_LENGTH,
        iv,
        AUTH_TAG_LENGTH,
        auth_tag,
        encrypted_data
      ].pack('Na*Na*Na*a*')
    end

    # Распаковывает зашифрованные данные
    #
    # @param packed_data [String] Упакованные данные
    # @return [Array] Массив [соль, iv, auth_tag, зашифрованные_данные]
    # @raise [CryptoError] при некорректном формате данных
    def unpack_encrypted_data(packed_data)
      offset = 0

      # Извлекаем соль
      salt_length = packed_data[offset, 4].unpack1('N')
      offset += 4
      raise CryptoError, 'Некорректная длина соли' unless salt_length == SALT_LENGTH

      salt = packed_data[offset, salt_length]
      offset += salt_length

      # Извлекаем IV
      iv_length = packed_data[offset, 4].unpack1('N')
      offset += 4
      raise CryptoError, 'Некорректная длина IV' unless iv_length == IV_LENGTH

      iv = packed_data[offset, iv_length]
      offset += iv_length

      # Извлекаем auth_tag
      auth_tag_length = packed_data[offset, 4].unpack1('N')
      offset += 4
      raise CryptoError, 'Некорректная длина auth_tag' unless auth_tag_length == AUTH_TAG_LENGTH

      auth_tag = packed_data[offset, auth_tag_length]
      offset += auth_tag_length

      # Остальные данные - зашифрованный контент
      encrypted_data = packed_data[offset..-1]

      [salt, iv, auth_tag, encrypted_data]
    end
  end
end
