# frozen_string_literal: true

RSpec.describe KeySloth::GitManager do
  let(:repo_url) { 'git@github.com:test/secrets.git' }
  let(:logger) { mock_logger }
  let(:git_manager) { described_class.new(repo_url, logger) }
  let(:temp_dir) { '/tmp/keysloth_test_repo' }

  before do
    # Делаем git доступным
    allow(Open3).to receive(:capture3).with('git --version').and_return(['', '',
                                                                         double(success?: true)])
  end

  describe '#initialize' do
    it 'creates git manager with valid SSH URL' do
      expect(git_manager.instance_variable_get(:@repo_url)).to eq(repo_url)
      expect(git_manager.instance_variable_get(:@logger)).to eq(logger)
    end

    it 'raises error with invalid URL' do
      expect do
        described_class.new('invalid_url', logger)
      end.to raise_error(KeySloth::RepositoryError, /SSH URL/)
    end

    it 'raises error with empty URL' do
      expect { described_class.new('', logger) }.to raise_error(KeySloth::RepositoryError, /пустым/)
    end

    it 'raises error when git is not available' do
      allow(Open3).to receive(:capture3).with('git --version').and_return(['', '',
                                                                           double(success?: false)])

      expect do
        described_class.new(repo_url,
                            logger)
      end.to raise_error(KeySloth::RepositoryError, /Git не установлен/)
    end
  end

  describe '#pull_encrypted_files' do
    let(:branch) { 'main' }

    it 'клонирует репозиторий, переключает ветку, тянет изменения и возвращает .enc файлы' do
      allow(Dir).to receive(:mktmpdir).and_return(temp_dir)

      # Порядок: clone -> rev-parse -> checkout -b --track -> fetch -> pull --ff-only
      expect(Open3).to receive(:capture3).with(anything, 'git', 'clone', '--quiet', '--depth', '1',
                                               repo_url, temp_dir, chdir: nil)
        .and_return(['', '', double(success?: true)]).ordered

      expect(Open3).to receive(:capture3).with(anything, 'git', 'rev-parse', '--verify', branch,
                                               chdir: temp_dir)
        .and_return(['', '', double(success?: false)]).ordered

      expect(Open3).to receive(:capture3).with(anything, 'git', 'checkout', '-b', branch,
                                               '--track', "origin/#{branch}", chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered

      expect(Open3).to receive(:capture3).with(anything, 'git', 'fetch', 'origin', branch,
                                               chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered

      expect(Open3).to receive(:capture3).with(anything, 'git', 'pull', '--ff-only', 'origin',
                                               branch, chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered

      allow(Dir).to receive(:glob).with('**/*.enc',
                                        base: temp_dir).and_return(['cert.cer.enc',
                                                                    'config.json.enc'])
      allow(File).to receive(:file?).and_return(true)
      allow(File).to receive(:read).with(File.join(temp_dir, 'cert.cer.enc')).and_return('enc1')
      allow(File).to receive(:read).with(File.join(temp_dir, 'config.json.enc')).and_return('enc2')

      result = git_manager.pull_encrypted_files(branch)

      expect(result).to eq([
                             { name: 'cert.cer.enc', content: 'enc1' },
                             { name: 'config.json.enc', content: 'enc2' }
                           ])
    end
  end

  describe '#prepare_repository' do
    let(:branch) { 'main' }

    it 'клонирует, чекаутит ветку и обновляет её' do
      allow(Dir).to receive(:mktmpdir).and_return(temp_dir)

      expect(Open3).to receive(:capture3).with(anything, 'git', 'clone', '--quiet', '--depth', '1',
                                               repo_url, temp_dir, chdir: nil)
        .and_return(['', '', double(success?: true)]).ordered
      expect(Open3).to receive(:capture3).with(anything, 'git', 'rev-parse', '--verify', branch,
                                               chdir: temp_dir)
        .and_return(['', '', double(success?: false)]).ordered
      expect(Open3).to receive(:capture3).with(anything, 'git', 'checkout', '-b', branch,
                                               '--track', "origin/#{branch}", chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered
      expect(Open3).to receive(:capture3).with(anything, 'git', 'fetch', 'origin', branch,
                                               chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered
      expect(Open3).to receive(:capture3).with(anything, 'git', 'pull', '--ff-only', 'origin',
                                               branch, chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered

      git_manager.prepare_repository(branch)
    end

    it 'ошибка если fast-forward невозможен и unshallow не помогает' do
      allow(Dir).to receive(:mktmpdir).and_return(temp_dir)
      allow(Open3).to receive(:capture3).with(anything, 'git', 'clone', '--quiet', '--depth', '1',
                                              repo_url, temp_dir, chdir: nil)
        .and_return(['', '', double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'rev-parse', '--verify', branch,
                                              chdir: temp_dir)
        .and_return(['', '', double(success?: false)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'checkout', '-b', branch, '--track',
                                              "origin/#{branch}", chdir: temp_dir)
        .and_return(['', '', double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'fetch', 'origin', branch,
                                              chdir: temp_dir)
        .and_return(['', '', double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'pull', '--ff-only', 'origin',
                                              branch, chdir: temp_dir)
        .and_return(['', 'ff failed', double(success?: false)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'fetch', '--unshallow',
                                              chdir: temp_dir)
        .and_return(['', '', double(success?: false)])

      expect do
        git_manager.prepare_repository(branch)
      end.to raise_error(KeySloth::RepositoryError, /git pull/)
    end
  end

  describe '#write_encrypted_files' do
    let(:encrypted_files) do
      [
        { path: 'cert.cer.enc', content: 'encrypted_cert' },
        { path: 'nested/config.json.enc', content: 'encrypted_config' }
      ]
    end

    before do
      git_manager.instance_variable_set(:@temp_dir, temp_dir)
      allow(Dir).to receive(:glob).and_return([])
      allow(File).to receive(:delete)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
    end

    it 'clears existing encrypted files and writes new ones' do
      git_manager.write_encrypted_files(encrypted_files)

      expect(FileUtils).to have_received(:mkdir_p).with("#{temp_dir}/nested")
      expect(File).to have_received(:write).with("#{temp_dir}/cert.cer.enc", 'encrypted_cert')
      expect(File).to have_received(:write).with("#{temp_dir}/nested/config.json.enc",
                                                 'encrypted_config')
    end

    it 'logs writing progress' do
      expect(logger).to receive(:info).with(/Записываем 2 зашифрованных файлов/)
      expect(logger).to receive(:debug).with(/Записан файл: cert.cer.enc/)
      expect(logger).to receive(:debug).with(%r{Записан файл: nested/config.json.enc})

      git_manager.write_encrypted_files(encrypted_files)
    end

    it 'handles file system errors' do
      allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError.new('Permission denied'))

      expect do
        git_manager.write_encrypted_files(encrypted_files)
      end.to raise_error(KeySloth::RepositoryError,
                         /Не удалось записать файлы/)
    end
  end

  describe '#commit_and_push' do
    let(:commit_message) { 'Update secrets' }
    let(:branch) { 'main' }

    before do
      git_manager.instance_variable_set(:@temp_dir, temp_dir)
    end

    it 'creates commit and pushes changes' do
      expect(Open3).to receive(:capture3).with(anything, 'git', 'add', '-A', chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered

      # status показывает изменения
      expect(Open3).to receive(:capture3).with(anything, 'git', 'status', '--porcelain',
                                               chdir: temp_dir)
        .and_return([' M file', '',
                     double(success?: true)]).ordered

      # git config must be present
      expect(Open3).to receive(:capture3).with(anything, 'git', 'config', '--get', 'user.name',
                                               chdir: temp_dir)
        .and_return(['Your Name', '',
                     double(success?: true)]).ordered
      expect(Open3).to receive(:capture3).with(anything, 'git', 'config', '--get', 'user.email',
                                               chdir: temp_dir)
        .and_return(['you@example.com', '',
                     double(success?: true)]).ordered

      expect(Open3).to receive(:capture3).with(anything, 'git', 'commit', '-m', commit_message,
                                               chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered
      expect(Open3).to receive(:capture3).with(anything, 'git', 'push', 'origin', branch,
                                               chdir: temp_dir)
        .and_return(['', '', double(success?: true)]).ordered

      git_manager.commit_and_push(commit_message, branch)
    end

    it 'skips commit when no changes present' do
      expect(Open3).to receive(:capture3).with(anything, 'git', 'add', '-A', chdir: temp_dir)
        .and_return(['', '', double(success?: true)])
      expect(Open3).to receive(:capture3).with(anything, 'git', 'status', '--porcelain',
                                               chdir: temp_dir)
        .and_return(['', '', double(success?: true)])
      expect(Open3).not_to receive(:capture3).with(anything, 'git', 'commit', '-m', commit_message,
                                                   chdir: temp_dir)
      expect(Open3).not_to receive(:capture3).with(anything, 'git', 'push', 'origin', branch,
                                                   chdir: temp_dir)

      git_manager.commit_and_push(commit_message, branch)
    end

    it 'logs commit and push progress' do
      expect(logger).to receive(:info).with(/Создаем коммит и отправляем/)
      expect(logger).to receive(:debug).with(/Создан коммит/)
      expect(logger).to receive(:debug).with(/Изменения отправлены/)
      expect(logger).to receive(:info).with(/Изменения успешно отправлены/)

      allow(Open3).to receive(:capture3).with(anything, 'git', 'add', '-A',
                                              chdir: temp_dir).and_return(['', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'status', '--porcelain',
                                              chdir: temp_dir).and_return(['M file', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'config', '--get', 'user.name',
                                              chdir: temp_dir).and_return(['User', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'config', '--get', 'user.email',
                                              chdir: temp_dir).and_return(['u@e', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'commit', '-m', commit_message,
                                              chdir: temp_dir).and_return(['', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'push', 'origin', branch,
                                              chdir: temp_dir).and_return(['', '',
                                                                           double(success?: true)])

      git_manager.commit_and_push(commit_message, branch)
    end

    it 'handles git errors during commit' do
      allow(Open3).to receive(:capture3).with(anything, 'git', 'add', '-A',
                                              chdir: temp_dir).and_return(['', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'status', '--porcelain',
                                              chdir: temp_dir).and_return(['M file', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'config', '--get', 'user.name',
                                              chdir: temp_dir).and_return(['User', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'config', '--get', 'user.email',
                                              chdir: temp_dir).and_return(['u@e', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'commit', '-m', commit_message,
                                              chdir: temp_dir).and_return(['', 'Commit failed',
                                                                           double(success?: false)])

      expect do
        git_manager.commit_and_push(commit_message,
                                    branch)
      end.to raise_error(KeySloth::RepositoryError, /Commit failed/)
    end
  end

  describe '#cleanup' do
    before do
      git_manager.instance_variable_set(:@temp_dir, temp_dir)
      allow(Dir).to receive(:exist?).with(temp_dir).and_return(true)
      allow(FileUtils).to receive(:remove_entry)
    end

    it 'removes temporary directory' do
      git_manager.cleanup

      expect(FileUtils).to have_received(:remove_entry).with(temp_dir)
      expect(git_manager.instance_variable_get(:@temp_dir)).to be_nil
    end

    it 'handles missing temporary directory gracefully' do
      git_manager.instance_variable_set(:@temp_dir, nil)

      expect { git_manager.cleanup }.not_to raise_error
      expect(FileUtils).not_to have_received(:remove_entry)
    end

    it 'logs cleanup process' do
      expect(logger).to receive(:debug).with(/Очищаем временную директорию/)

      git_manager.cleanup
    end
  end

  describe 'SSH аутентификация' do
    it 'использует KEYSLOTH_SSH_KEY_PATH через GIT_SSH_COMMAND' do
      allow(Dir).to receive(:mktmpdir).and_return(temp_dir)
      ENV['KEYSLOTH_SSH_KEY_PATH'] = '/home/test/.ssh/custom_key'

      begin
        mgr = described_class.new(repo_url, logger)
        expect(Open3).to receive(:capture3) do |env, *_args|
          expect(env['GIT_SSH_COMMAND']).to include('-i /home/test/.ssh/custom_key')
          ['', '', double(success?: true)]
        end

        # Любая git-команда, например clone
        mgr.send(:clone_repository)
      ensure
        ENV.delete('KEYSLOTH_SSH_KEY_PATH')
      end
    end

    it 'создает временные ключи из ENV и настраивает GIT_SSH_COMMAND' do
      ENV['SSH_PRIVATE_KEY'] = 'private_key_content'
      ENV['SSH_PUBLIC_KEY'] = 'public_key_content'
      allow(Dir).to receive(:mktmpdir).and_return('/tmp/keysloth_ssh')
      expect(File).to receive(:write).with('/tmp/keysloth_ssh/id_rsa', 'private_key_content')
      expect(File).to receive(:chmod).with(0o600, '/tmp/keysloth_ssh/id_rsa')
      expect(File).to receive(:write).with('/tmp/keysloth_ssh/id_rsa.pub', 'public_key_content')

      mgr = described_class.new(repo_url, logger)

      expect(Open3).to receive(:capture3) do |env, *_args|
        expect(env['GIT_SSH_COMMAND']).to include('-i /tmp/keysloth_ssh/id_rsa')
        ['', '', double(success?: true)]
      end

      allow(Dir).to receive(:mktmpdir).and_return(temp_dir)
      mgr.send(:clone_repository)

      ENV.delete('SSH_PRIVATE_KEY')
      ENV.delete('SSH_PUBLIC_KEY')
    end
  end

  describe 'error handling' do
    it 'validates repository URL format' do
      expect do
        described_class.new('https://github.com/test/repo.git', logger)
      end.to raise_error(KeySloth::RepositoryError, /SSH URL/)
    end

    it 'raises error when git is not available' do
      allow(Open3).to receive(:capture3).with('git --version').and_return(['', '',
                                                                           double(success?: false)])
      expect do
        described_class.new(repo_url,
                            logger)
      end.to raise_error(KeySloth::RepositoryError, /Git не установлен/)
    end

    it 'raises error when user.name/email not configured' do
      git_manager.instance_variable_set(:@temp_dir, temp_dir)
      allow(Open3).to receive(:capture3).with(anything, 'git', 'add', '-A',
                                              chdir: temp_dir).and_return(['', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'status', '--porcelain',
                                              chdir: temp_dir).and_return(['M file', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'config', '--get', 'user.name',
                                              chdir: temp_dir).and_return(['', '',
                                                                           double(success?: true)])
      allow(Open3).to receive(:capture3).with(anything, 'git', 'config', '--get', 'user.email',
                                              chdir: temp_dir).and_return(['', '',
                                                                           double(success?: true)])

      expect do
        git_manager.commit_and_push('msg', 'main')
      end.to raise_error(KeySloth::RepositoryError, /user.name/)
    end
  end
end
