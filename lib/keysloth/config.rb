# frozen_string_literal: true

require 'yaml'
require 'pathname'

module KeySloth
  # Класс для управления конфигурацией KeySloth
  #
  # Поддерживает загрузку конфигурации из YAML файла .keyslothrc.
  # Параметры командной строки имеют приоритет над файлом конфигурации.
  #
  # @example Структура файла .keyslothrc
  #   repo_url: "git@github.com:company/secrets.git"
  #   branch: "main"
  #   local_path: "./secrets"
  #   backup_count: 3
  #
  # @example Использование
  #   config = KeySloth::Config.load('.keyslothrc')
  #   merged = config.merge(repo_url: 'override_url')
  #
  # @author KeySloth Team
  # @since 0.1.0
  class Config
    # Значения конфигурации по умолчанию
    DEFAULT_CONFIG = {
      branch: 'main',
      backup_count: 3,
      local_path: './secrets'
    }.freeze

    # Инициализация объекта конфигурации
    #
    # @param config_hash [Hash] Хеш с параметрами конфигурации
    def initialize(config_hash = {})
      @config = DEFAULT_CONFIG.merge(symbolize_keys(config_hash))
    end

    # Загружает конфигурацию из файла
    #
    # @param config_file [String, nil] Путь к файлу конфигурации
    # @return [Config] Объект конфигурации
    # @raise [ConfigurationError] при ошибках чтения файла конфигурации
    def self.load(config_file = nil)
      config_path = resolve_config_path(config_file)

      if config_path && File.exist?(config_path)
        begin
          yaml_content = YAML.load_file(config_path)
          new(yaml_content || {})
        rescue StandardError => e
          raise ConfigurationError, "Ошибка чтения конфигурации из #{config_path}: #{e.message}", e
        end
      else
        new
      end
    end

    # Объединяет текущую конфигурацию с новыми параметрами
    #
    # @param overrides [Hash] Параметры для переопределения
    # @return [Hash] Объединенная конфигурация
    def merge(overrides = {})
      @config.merge(symbolize_keys(overrides))
    end

    # Возвращает значение конфигурации по ключу
    #
    # @param key [Symbol, String] Ключ конфигурации
    # @return [Object] Значение конфигурации
    def [](key)
      @config[key.to_sym]
    end

    # Устанавливает значение конфигурации
    #
    # @param key [Symbol, String] Ключ конфигурации
    # @param value [Object] Значение конфигурации
    def []=(key, value)
      @config[key.to_sym] = value
    end

    # Возвращает все параметры конфигурации
    #
    # @return [Hash] Хеш конфигурации
    def to_h
      @config.dup
    end

    # Валидирует обязательные параметры конфигурации
    #
    # @param required_keys [Array<Symbol>] Список обязательных ключей
    # @raise [ValidationError] при отсутствии обязательных параметров
    def validate!(required_keys = [])
      missing_keys = required_keys.select { |key| @config[key].nil? || @config[key].to_s.empty? }

      unless missing_keys.empty?
        raise ValidationError, "Отсутствуют обязательные параметры: #{missing_keys.join(', ')}"
      end
    end

    private

    # Преобразует строковые ключи в символы
    #
    # @param hash [Hash] Исходный хеш
    # @return [Hash] Хеш с символьными ключами
    def symbolize_keys(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value
      end
    end

    # Определяет путь к файлу конфигурации
    #
    # @param config_file [String, nil] Явно указанный путь к файлу
    # @return [String, nil] Путь к файлу конфигурации или nil
    def self.resolve_config_path(config_file)
      return config_file if config_file

      # Ищем .keyslothrc в текущей директории и домашней директории
      ['.keyslothrc', File.expand_path('~/.keyslothrc')].find do |path|
        File.exist?(path)
      end
    end

    private_class_method :resolve_config_path
  end
end
