# frozen_string_literal: true

RSpec.describe KeySloth::Logger do
  let(:output) { StringIO.new }
  let(:logger) { described_class.new(level: :info, output: output) }

  describe '#initialize' do
    it 'creates logger with default level' do
      expect { described_class.new }.not_to raise_error
    end

    it 'sets custom log level' do
      debug_logger = described_class.new(level: :debug)
      expect(debug_logger.level).to eq(Logger::DEBUG)
    end

    it 'raises error for unknown log level' do
      expect do
        described_class.new(level: :unknown)
      end.to raise_error(ArgumentError, /Неизвестный уровень/)
    end
  end

  describe 'basic logging methods' do
    it 'logs info messages' do
      logger.info('Test info message')
      expect(output.string).to include('INFO: Test info message')
    end

    it 'logs debug messages' do
      debug_logger = described_class.new(level: :debug, output: output)
      debug_logger.debug('Test debug message')
      expect(output.string).to include('DEBUG: Test debug message')
    end

    it 'logs warnings' do
      logger.warn('Test warning')
      expect(output.string).to include('WARN: Test warning')
    end

    it 'logs errors with exception details' do
      exception = StandardError.new('Test exception')
      exception.set_backtrace(%w[line1 line2])

      debug_logger = described_class.new(level: :debug, output: output)
      debug_logger.error('Test error', exception)

      expect(output.string).to include('ERROR: Test error: Test exception')
      expect(output.string).to include('DEBUG: Backtrace: line1')
    end
  end

  describe '#audit' do
    it 'logs audit information' do
      details = { repo_url: 'git@example.com:repo.git', branch: 'main' }
      logger.audit('pull_start', details)

      output_content = output.string
      expect(output_content).to include('[AUDIT]')
      expect(output_content).to include('Operation: pull_start')
      expect(output_content).to include('repo_url=git@example.com:repo.git')
      expect(output_content).to include('branch=main')
    end

    it 'logs audit without details' do
      logger.audit('test_operation')

      output_content = output.string
      expect(output_content).to include('[AUDIT]')
      expect(output_content).to include('Operation: test_operation')
    end

    it 'includes UTC timestamp' do
      logger.audit('test_operation')

      expect(output.string).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/)
    end

    it 'sanitizes sensitive values' do
      details = { password: 'secret123', repo_url: 'git@example.com:repo.git' }
      logger.audit('test_operation', details)

      output_content = output.string
      expect(output_content).to include('password=[HIDDEN]')
      expect(output_content).to include('repo_url=git@example.com:repo.git')
    end
  end

  describe '#security_log' do
    it 'logs successful operations' do
      details = { files_count: 5, repo_url: 'git@example.com:repo.git' }
      logger.security_log('pull', :success, duration: 2.5, details: details)

      output_content = output.string
      expect(output_content).to include('[SECURITY] PULL: SUCCESS')
      expect(output_content).to include('(2.5s)')
      expect(output_content).to include('files_count=5')
    end

    it 'logs failed operations as errors' do
      details = { error: 'CryptoError' }
      logger.security_log('push', :failure, details: details)

      output_content = output.string
      expect(output_content).to include('ERROR')
      expect(output_content).to include('[SECURITY] PUSH: FAILURE')
      expect(output_content).to include('error=CryptoError')
    end

    it 'logs warnings for warning operations' do
      logger.security_log('validate', :warning, details: { message: 'Some files corrupted' })

      output_content = output.string
      expect(output_content).to include('WARN')
      expect(output_content).to include('[SECURITY] VALIDATE: WARNING')
    end

    it 'duplicates failures to audit log' do
      details = { error: 'NetworkError' }
      logger.security_log('pull', :failure, duration: 1.0, details: details)

      output_content = output.string
      expect(output_content).to include('[SECURITY] PULL: FAILURE')
      expect(output_content).to include('[AUDIT]')
      expect(output_content).to include('Operation: pull')
    end
  end

  describe '#level=' do
    it 'changes log level dynamically' do
      logger.level = :debug
      expect(logger.level).to eq(Logger::DEBUG)

      logger.level = :error
      expect(logger.level).to eq(Logger::ERROR)
    end
  end

  describe 'value sanitization' do
    let(:logger_with_debug) { described_class.new(level: :debug, output: output) }

    it 'hides password values' do
      details = { user_password: 'secret123' }
      logger.audit('test', details)

      expect(output.string).to include('user_password=[HIDDEN]')
    end

    it 'hides key values' do
      details = { secret_key: 'abc123xyz' }
      logger.audit('test', details)

      expect(output.string).to include('secret_key=[HIDDEN]')
    end

    it 'hides secret values' do
      details = { client_secret: 'very_secret' }
      logger.audit('test', details)

      expect(output.string).to include('client_secret=[HIDDEN]')
    end

    it 'truncates long values' do
      long_value = 'a' * 100
      details = { long_text: long_value }
      logger.audit('test', details)

      expect(output.string).to include('long_text=' + ('a' * 50) + '...')
    end

    it 'handles nil values' do
      details = { empty_value: nil }
      logger.audit('test', details)

      expect(output.string).to include('empty_value=nil')
    end

    it 'preserves normal values' do
      details = { normal_field: 'normal_value' }
      logger.audit('test', details)

      expect(output.string).to include('normal_field=normal_value')
    end
  end
end
