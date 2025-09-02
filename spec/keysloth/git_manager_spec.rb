# frozen_string_literal: true

RSpec.describe KeySloth::GitManager do
  let(:repo_url) { 'git@github.com:test/secrets.git' }
  let(:logger) { mock_logger }
  let(:git_manager) { described_class.new(repo_url, logger) }
  let(:temp_dir) { '/tmp/keysloth_test_repo' }

  # Mock Rugged classes - we mock them to avoid dependency
  let(:rugged_repository_class) { class_double('Rugged::Repository') }
  let(:rugged_credentials_class) { class_double('Rugged::Credentials::SshKey') }
  let(:rugged_commit_class) { class_double('Rugged::Commit') }
  let(:rugged_signature_class) { class_double('Rugged::Signature') }
  let(:rugged_error_class) { class_double('Rugged::Error') }

  # Mock objects
  let(:mock_repository) { double('Repository') }
  let(:mock_index) { double('Index') }
  let(:mock_branch) { double('Branch') }
  let(:mock_target) { double('Commit') }
  let(:mock_blob) { double('Blob') }
  let(:mock_credentials) { double('SshKey') }
  let(:mock_signature) { double('Signature') }

  before do
    # Mock Rugged constants
    stub_const('Rugged::Repository', rugged_repository_class)
    stub_const('Rugged::Credentials::SshKey', rugged_credentials_class)
    stub_const('Rugged::Commit', rugged_commit_class)
    stub_const('Rugged::Signature', rugged_signature_class)
    stub_const('Rugged::Error', Class.new(StandardError))

    # Mock git availability check
    allow(Open3).to receive(:capture3).with('git --version').and_return(['', '',
                                                                         double(success?: true)])

    # Mock SSH key files
    allow(File).to receive(:expand_path).with('~/.ssh/id_rsa').and_return('/home/test/.ssh/id_rsa')
    allow(File).to receive(:expand_path).with('~/.ssh/id_rsa.pub').and_return('/home/test/.ssh/id_rsa.pub')
    allow(File).to receive(:exist?).with('/home/test/.ssh/id_rsa').and_return(true)
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
    let(:encrypted_files) do
      [
        { name: 'cert.cer.enc', content: 'encrypted_cert_content' },
        { name: 'config.json.enc', content: 'encrypted_config_content' }
      ]
    end

    before do
      allow(Dir).to receive(:mktmpdir).and_return(temp_dir)
      allow(rugged_repository_class).to receive(:clone_at).and_return(mock_repository)
      allow(mock_repository).to receive(:branches).and_return({
                                                                'main' => mock_branch,
                                                                'origin/main' => mock_branch
                                                              })
      allow(mock_repository).to receive(:checkout)
      allow(mock_repository).to receive(:index).and_return(mock_index)
      allow(mock_index).to receive(:each)
      allow(rugged_credentials_class).to receive(:new).and_return(mock_credentials)
    end

    it 'clones repository and returns encrypted files' do
      # Mock index entries
      entries = [
        { path: 'cert.cer.enc', oid: 'blob_oid_1' },
        { path: 'config.json.enc', oid: 'blob_oid_2' },
        { path: 'regular.txt', oid: 'blob_oid_3' } # Should be ignored
      ]

      allow(mock_index).to receive(:each).and_yield(entries[0]).and_yield(entries[1]).and_yield(entries[2])

      # Mock blob lookups
      blob1 = double('Blob', content: 'encrypted_cert_content')
      blob2 = double('Blob', content: 'encrypted_config_content')

      allow(mock_repository).to receive(:lookup).with('blob_oid_1').and_return(blob1)
      allow(mock_repository).to receive(:lookup).with('blob_oid_2').and_return(blob2)

      result = git_manager.pull_encrypted_files(branch)

      expect(result.size).to eq(2)
      expect(result[0][:name]).to eq('cert.cer.enc')
      expect(result[0][:content]).to eq('encrypted_cert_content')
      expect(result[1][:name]).to eq('config.json.enc')
      expect(result[1][:content]).to eq('encrypted_config_content')
    end

    it 'handles repository errors' do
      allow(rugged_repository_class).to receive(:clone_at).and_raise(Rugged::Error.new('Network error'))

      expect do
        git_manager.pull_encrypted_files(branch)
      end.to raise_error(KeySloth::RepositoryError,
                         /Git операция не удалась/)
    end

    it 'logs operation progress' do
      allow(mock_index).to receive(:each)

      expect(logger).to receive(:info).with(/Клонируем репозиторий/)
      expect(logger).to receive(:info).with(/Найдено \d+ зашифрованных файлов/)

      git_manager.pull_encrypted_files(branch)
    end
  end

  describe '#prepare_repository' do
    let(:branch) { 'main' }

    before do
      allow(Dir).to receive(:mktmpdir).and_return(temp_dir)
      allow(rugged_repository_class).to receive(:clone_at).and_return(mock_repository)
      allow(mock_repository).to receive(:branches).and_return({
                                                                'main' => mock_branch,
                                                                'origin/main' => mock_branch
                                                              })
      allow(mock_repository).to receive(:checkout)
      allow(mock_branch).to receive(:target_id).and_return('commit_sha')
      allow(rugged_credentials_class).to receive(:new).and_return(mock_credentials)
    end

    it 'clones repository and checks out branch' do
      git_manager.prepare_repository(branch)

      expect(rugged_repository_class).to have_received(:clone_at).with(
        repo_url,
        temp_dir,
        credentials: mock_credentials
      )
      expect(mock_repository).to have_received(:checkout).with(mock_branch)
    end

    it 'raises error if branch is not up to date' do
      local_branch = double('Branch', target_id: 'local_sha')
      remote_branch = double('Branch', target_id: 'remote_sha')

      allow(mock_repository).to receive(:branches).and_return({
                                                                'main' => local_branch,
                                                                'origin/main' => remote_branch
                                                              })

      expect do
        git_manager.prepare_repository(branch)
      end.to raise_error(KeySloth::RepositoryError,
                         /не синхронизирована/)
    end

    it 'logs preparation progress' do
      expect(logger).to receive(:info).with(/Подготавливаем репозиторий/)

      git_manager.prepare_repository(branch)
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
      git_manager.instance_variable_set(:@repository, mock_repository)
      allow(mock_repository).to receive(:index).and_return(mock_index)
      allow(mock_index).to receive(:add_all)
      allow(mock_index).to receive(:write)
      allow(mock_index).to receive(:write_tree).and_return('tree_sha')
      allow(mock_repository).to receive(:diff_workdir_to_index).and_return(double(deltas: [double]))
      allow(mock_repository).to receive(:diff_index_to_tree).and_return(double(deltas: []))
      allow(mock_repository).to receive(:head).and_return(double(target: double(tree: 'tree_sha')))
      allow(rugged_commit_class).to receive(:create).and_return('commit_sha')
      allow(mock_repository).to receive(:push)
      allow(rugged_signature_class).to receive(:new).and_return(mock_signature)
      allow(rugged_credentials_class).to receive(:new).and_return(mock_credentials)
    end

    it 'creates commit and pushes changes' do
      git_manager.commit_and_push(commit_message, branch)

      expect(mock_index).to have_received(:add_all)
      expect(mock_index).to have_received(:write)
      expect(rugged_commit_class).to have_received(:create)
      expect(mock_repository).to have_received(:push).with('origin', ["refs/heads/#{branch}"],
                                                           credentials: mock_credentials)
    end

    it 'skips commit when no changes present' do
      allow(mock_repository).to receive(:diff_workdir_to_index).and_return(double(deltas: []))
      allow(mock_repository).to receive(:diff_index_to_tree).and_return(double(deltas: []))

      git_manager.commit_and_push(commit_message, branch)

      expect(rugged_commit_class).not_to have_received(:create)
      expect(mock_repository).not_to have_received(:push)
    end

    it 'logs commit and push progress' do
      expect(logger).to receive(:info).with(/Создаем коммит и отправляем/)
      expect(logger).to receive(:debug).with(/Создан коммит/)
      expect(logger).to receive(:debug).with(/Изменения отправлены/)
      expect(logger).to receive(:info).with(/Изменения успешно отправлены/)

      git_manager.commit_and_push(commit_message, branch)
    end

    it 'handles git errors during commit' do
      allow(rugged_commit_class).to receive(:create).and_raise(Rugged::Error.new('Commit failed'))

      expect do
        git_manager.commit_and_push(commit_message,
                                    branch)
      end.to raise_error(KeySloth::RepositoryError, /Не удалось отправить изменения/)
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

  describe 'SSH credentials handling' do
    context 'with local SSH keys' do
      it 'uses standard SSH keys from ~/.ssh' do
        # This is tested implicitly in other tests through mocking
        expect(File).to receive(:exist?).with('/home/test/.ssh/id_rsa').and_return(true)
        allow(rugged_credentials_class).to receive(:new).with(
          username: 'git',
          publickey: '/home/test/.ssh/id_rsa.pub',
          privatekey: '/home/test/.ssh/id_rsa'
        ).and_return(mock_credentials)

        git_manager.send(:create_ssh_credentials)
      end
    end

    context 'with environment SSH keys' do
      before do
        ENV['SSH_PRIVATE_KEY'] = 'private_key_content'
        ENV['SSH_PUBLIC_KEY'] = 'public_key_content'
        allow(Dir).to receive(:mktmpdir).and_return('/tmp/keysloth_ssh')
        allow(File).to receive(:write)
        allow(File).to receive(:chmod)
      end

      after do
        ENV.delete('SSH_PRIVATE_KEY')
        ENV.delete('SSH_PUBLIC_KEY')
      end

      it 'creates temporary SSH keys from environment' do
        allow(rugged_credentials_class).to receive(:new).with(
          username: 'git',
          publickey: '/tmp/keysloth_ssh/id_rsa.pub',
          privatekey: '/tmp/keysloth_ssh/id_rsa'
        ).and_return(mock_credentials)

        expect(File).to receive(:write).with('/tmp/keysloth_ssh/id_rsa', 'private_key_content')
        expect(File).to receive(:write).with('/tmp/keysloth_ssh/id_rsa.pub', 'public_key_content')
        expect(File).to receive(:chmod).with(0o600, '/tmp/keysloth_ssh/id_rsa')

        git_manager.send(:create_ssh_credentials)
      end
    end
  end

  describe 'error handling' do
    it 'handles authentication errors' do
      allow(File).to receive(:exist?).with('/home/test/.ssh/id_rsa').and_return(false)

      expect do
        git_manager.send(:create_ssh_credentials)
      end.to raise_error(KeySloth::AuthenticationError,
                         /SSH ключ не найден/)
    end

    it 'validates repository URL format' do
      expect do
        described_class.new('https://github.com/test/repo.git',
                            logger)
      end.to raise_error(KeySloth::RepositoryError, /SSH URL/)
    end
  end
end
