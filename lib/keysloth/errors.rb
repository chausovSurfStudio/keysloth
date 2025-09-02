# frozen_string_literal: true

module KeySloth
  # Базовый класс для всех ошибок KeySloth
  class KeySlothError < StandardError
    # Инициализация ошибки с сообщением и причиной
    #
    # @param message [String] Сообщение об ошибке
    # @param cause [Exception, nil] Исходная причина ошибки (опционально)
    def initialize(message = nil, cause = nil)
      super(message)
      @cause = cause
    end

    # Возвращает исходную причину ошибки
    #
    # @return [Exception, nil] Исходная причина ошибки или nil
    attr_reader :cause
  end

  # Ошибки криптографических операций
  class CryptoError < KeySlothError; end

  # Ошибки работы с Git репозиторием
  class RepositoryError < KeySlothError; end

  # Ошибки файловой системы
  class FileSystemError < KeySlothError; end

  # Ошибки конфигурации
  class ConfigurationError < KeySlothError; end

  # Ошибки аутентификации
  class AuthenticationError < KeySlothError; end

  # Ошибки валидации входных данных
  class ValidationError < KeySlothError; end

  # Ошибки сетевого соединения
  class NetworkError < KeySlothError; end
end
