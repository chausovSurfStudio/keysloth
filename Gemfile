# frozen_string_literal: true

source 'https://rubygems.org'

# Указываем основную спецификацию gem'а
gemspec

group :development, :test do
  gem 'pry', '~> 0.14' # Отладка
  gem 'rake', '~> 13.0' # Задачи
end

group :test do
  gem 'timecop', '~> 0.9'  # Мокирование времени для тестов
  gem 'webmock', '~> 3.18' # Мокирование HTTP запросов для тестов
end
