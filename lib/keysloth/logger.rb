# frozen_string_literal: true

require 'logger'

module KeySloth
  # Класс для многоуровневого логирования KeySloth
  #
  # Обеспечивает логирование с различными уровнями детализации:
  # - ERROR: только критические ошибки
  # - INFO: основная информация о процессе (по умолчанию)
  # - DEBUG: подробная отладочная информация
  #
  # @example Использование логгера
  #   logger = KeySloth::Logger.new
  #   logger.info("Начинаем операцию")
  #   logger.debug("Подробная информация")
  #   logger.error("Критическая ошибка")
  #
  # @author KeySloth Team
  # @since 0.1.0
  class Logger
    # Инициализация логгера
    #
    # @param level [Symbol] Уровень логирования (:error, :info, :debug)
    # @param output [IO] Поток вывода (по умолчанию STDOUT)
    def initialize(level: :info, output: $stdout)
      @logger = ::Logger.new(output)
      @logger.level = log_level_constant(level)
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
    end

    # Логирование информационных сообщений
    #
    # @param message [String] Сообщение для логирования
    def info(message)
      @logger.info(message)
    end

    # Логирование отладочных сообщений
    #
    # @param message [String] Сообщение для логирования
    def debug(message)
      @logger.debug(message)
    end

    # Логирование предупреждений
    #
    # @param message [String] Сообщение для логирования
    def warn(message)
      @logger.warn(message)
    end

    # Логирование ошибок
    #
    # @param message [String] Сообщение об ошибке
    # @param exception [Exception, nil] Исключение для детального логирования (опционально)
    def error(message, exception = nil)
      if exception
        @logger.error("#{message}: #{exception.message}")
        @logger.debug("Backtrace: #{exception.backtrace.join("\n")}")
      else
        @logger.error(message)
      end
    end

    # Изменяет уровень логирования
    #
    # @param level [Symbol] Новый уровень логирования (:error, :info, :debug)
    def level=(level)
      @logger.level = log_level_constant(level)
    end

    # Возвращает текущий уровень логирования
    #
    # @return [Integer] Константа уровня логирования
    def level
      @logger.level
    end

    # Аудит логирование для операций безопасности
    #
    # @param operation [String] Тип операции (pull, push, validate, etc.)
    # @param details [Hash] Детали операции
    def audit(operation, details = {})
      timestamp = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')

      audit_message = "[AUDIT] #{timestamp} | Operation: #{operation}"

      # Добавляем детали если они есть
      unless details.empty?
        details_str = details.map { |k, v| "#{k}=#{sanitize_log_value(v, k)}" }.join(', ')
        audit_message += " | #{details_str}"
      end

      @logger.info(audit_message)
    end

    # Логирование операций безопасности с метриками
    #
    # @param operation [String] Тип операции
    # @param result [Symbol] Результат операции (:success, :failure, :warning)
    # @param duration [Float] Длительность операции в секундах (опционально)
    # @param details [Hash] Дополнительные детали
    def security_log(operation, result, duration: nil, details: {})
      level_method = case result
                     when :success then :info
                     when :failure then :error
                     when :warning then :warn
                     else :info
                     end

      message = "[SECURITY] #{operation.upcase}: #{result.to_s.upcase}"
      message += " (#{duration.round(2)}s)" if duration

      unless details.empty?
        details_str = details.map { |k, v| "#{k}=#{sanitize_log_value(v, k)}" }.join(', ')
        message += " | #{details_str}"
      end

      send(level_method, message)

      # Дублируем критические ошибки в аудит лог
      audit(operation, details.merge(result: result, duration: duration)) if result == :failure
    end

    private

    # Преобразует символьный уровень в константу Logger
    #
    # @param level [Symbol] Символьный уровень логирования
    # @return [Integer] Константа уровня логирования
    # @raise [ArgumentError] при неизвестном уровне логирования
    def log_level_constant(level)
      case level
      when :debug
        ::Logger::DEBUG
      when :info
        ::Logger::INFO
      when :warn
        ::Logger::WARN
      when :error
        ::Logger::ERROR
      else
        raise ArgumentError, "Неизвестный уровень логирования: #{level}"
      end
    end

    # Очищает значения для безопасного логирования
    #
    # @param value [Object] Значение для очистки
    # @param key [Object] Ключ (опционально) для дополнительной проверки
    # @return [String] Очищенное значение
    def sanitize_log_value(value, key = nil)
      return 'nil' if value.nil?

      str_value = value.to_s
      key_str = key.to_s if key

      # Скрываем пароли и ключи (проверяем и ключ и значение)
      sensitive_pattern = /password|key|secret|token/i
      return '[HIDDEN]' if str_value.match?(sensitive_pattern) ||
                           key_str&.match?(sensitive_pattern)

      # Обрезаем длинные значения
      return "#{str_value[0, 50]}..." if str_value.length > 50

      str_value
    end
  end
end
