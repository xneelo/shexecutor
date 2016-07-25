require 'spec_helper'
require 'shexecutor.rb'
require 'tempfile'
require 'mocks/kernel.rb'
require 'mocks/result.rb'
require 'fileutils'

def temp_file_path(seed)
  file = Tempfile.new(seed)
  path = file.path
  file.close
  FileUtils.touch(path)
  File.chmod(0744, path)
  path
end

def ignore_tempfile_bug_on_older_rubies(ex)
  if ex.message == 'stream closed'
    puts "INDETERMINATE RESULT: Tempfile bug on older versions of ruby. Test result unreliable, but not a failure per se. Subsequent runs should succeed"
  else
    fail
  end
end

describe 'Executor' do
  before :each do
    @executable_file = temp_file_path("testingargumenterror")
    `echo "ls" >> #{@executable_file}`
  end

  context 'when initialized with no options' do
    it 'should set default options' do
      @iut = SHExecutor::Executor.new
    end
  end

  context 'when initialized with options' do
    it 'should remember the options' do
      iut_options = {
        :timeout => -1,
        :protect_against_injection=>true,
        :stdout_path => '/log/testlog',
        :stderr_path => '/log/testlog',
        :append_stdout_path => false,
        :append_stderr_path => false,
        :replace => false,
        :wait_for_completion => true,
        :timeout_sig_kill_retry => 500
      }
      @iut = SHExecutor::Executor.new(iut_options)
      expect(@iut.options).to eq(iut_options)
    end
  end

  context 'when initialized with some but not all options' do
    it 'should remember the options provided and default the rest' do
      expected_options = ::SHExecutor::default_options
      expected_options[:wait_for_completion] = false
      iut_options = {
        :wait_for_completion => false
      }
      @iut = SHExecutor::Executor.new(iut_options)
      expect(@iut.options).to eq(expected_options)
    end
  end

  context 'when initialized with one or more invalid options' do
    it 'validate should raise an ArgumentError' do
      iut = SHExecutor::Executor.new({:application_path => nil})
      expect{
        iut.validate
      }.to raise_error(ArgumentError, "No application path provided")
      iut = SHExecutor::Executor.new({:application_path => ""})
      expect{
        iut.validate
      }.to raise_error(ArgumentError, "No application path provided")
      iut = SHExecutor::Executor.new({:application_path => "/kjsdfhgjkgsjk"})
      expect{
        iut.validate
      }.to raise_error(ArgumentError, "Application path not found")
      path = temp_file_path("testingargumenterror")
      iut = SHExecutor::Executor.new({:application_path => path})
      error_received = false
      begin
        iut.validate
      rescue => ex
        error_received = (ex.class == ArgumentError) and (ex.message.include?("Suspected injection vulnerability due to space in application_path or the object being marked as 'tainted' by Ruby. Turn off strict checking if you are sure by setting :protect_against_injection to false"))
      end
      expect(error_received).to eq(true)
    end
  end

  context 'when initialized with valid options' do
    it 'validate should not raise an exception' do
      iut = SHExecutor::Executor.new({:application_path => @executable_file, :protect_against_injection => false})
      iut.validate
    end
  end

  context "when asked to execute" do
    it 'should clear stderr and stdout before execution' do
      test_command = "/bin/echo"
      test_params = ["Hello"]
      iut = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => test_command, :params => test_params})
      iut.stdout = "stdout before"
      iut.stderr = "error before"
      iut.execute
      iut.flush
      expect(iut.stderr).to be_nil
      expect(iut.stdout).to eq("Hello\n")
    end
  end

  context 'when asked to execute, replacing the current process' do
    it 'should use exec with the command and parameters specified' do
      test_command = "/bin/ls"
      test_params = ["/tmp/"]
      iut = SHExecutor::Executor.new({:replace => true, :application_path => test_command, :params => test_params})
      iut.execute
      expect(Kernel::last_command).to eq(test_command)
      expect(Kernel::last_params).to eq(*test_params)
    end

    it 'should use exec with the command if no parameters are specified and replacing' do
      test_command = "/bin/ls"
      iut = SHExecutor::Executor.new({:replace => true, :application_path => test_command})
      iut.execute
      expect(Kernel::last_command).to eq(test_command)
      expect(Kernel::last_params).to be_nil
    end

    it 'should use exec with the command if no parameters are specified and not waiting for completion' do
      test_command = "/bin/ls"
      iut = SHExecutor::Executor.new({:application_path => test_command, :wait_for_completion => true})
      iut.execute
    end

    it 'should validate' do
      iut = SHExecutor::Executor.new({:replace => true})
      expect{
        iut.execute
      }.to raise_error(ArgumentError, "No application path provided")
    end

    it 'should not replace if replace is not true' do
      iut = SHExecutor::Executor.new({:application_path => "/bin/ls", :replace => false})
      Kernel::last_command = "not executed"
      iut.execute
      expect(Kernel::last_command).to eq("not executed")

      iut = SHExecutor::Executor.new({:application_path => "/bin/ls", :replace => 'blah ignore this'})
      iut.execute
      expect(Kernel::last_command).to eq("not executed")
    end
  end

  context 'when not waiting for completion' do
    it 'should execute the command without blocking' do
      test_command = "/bin/sleep"
      test_params = ["2"]
      iut = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => test_command, :params => test_params})
      before = Time.now
      iut.execute
      after = Time.now
      expect(after - before).to be < 0.2
    end

    it 'should validate' do
      iut = SHExecutor::Executor.new({:wait_for_completion => false})
      expect{
        iut.execute
      }.to raise_error(ArgumentError, "No application path provided")
    end
  end

  context 'when asking for the status of the executor' do
    it 'should return "not executed" if execute has not been called' do
      test_command = "/bin/sleep"
      test_params = ["2"]
      iut = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => test_command, :params => test_params})
      expect(iut.status).to eq("not executed")
    end

    it 'should return the current process status if the process is executing' do
      test_command = "/bin/sleep"
      test_params = ["2"]
      iut = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => test_command, :params => test_params})
      iut.execute
      status = iut.status
      puts "status: #{status}"
      running = ((status == "run") or (status == "sleep"))
      expect(running).to eq(true)
    end

    it 'should return "no longer executing" if the process has stopped for what-ever reason' do
      test_command = "/bin/echo"
      test_params = ["I ran"]
      iut = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => test_command, :params => test_params})
      iut.execute
      sleep 1
      expect(iut.status).to eq("no longer executing")
    end
  end

  context 'when asking for the result of execution' do
    it 'should return nil if the process has not executed yet' do
      test_command = "/bin/sleep"
      test_params = ["1"]
      iut = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => test_command, :params => test_params})
      expect(iut.result).to be_nil
    end

    it 'should return nil if the process is still executing' do
      test_command = "/bin/sleep"
      test_params = ["1"]
      iut = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => test_command, :params => test_params})
      iut.execute
      expect(iut.result).to be_nil
    end

    it 'should return a Process::Status object if the process has executed, but is no longer, for what-ever reason' do
      test_command = "/bin/sleep"
      test_params = ["1"]
      iut = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => test_command, :params => test_params})
      iut.execute 
      sleep 2
      expect(iut.result.class).to eq(Process::Status)
    end
  end

  context 'when asked to execute and block' do
    it 'should raise a Timeout::Error if a timeout is specified and the process does not exit before' do
      begin
        test_command = "/bin/sleep"
        test_params = ["5"]
        iut = SHExecutor::Executor.new({:timeout => 1, :wait_for_completion => true, :application_path => test_command, :params => test_params})
        before = Time.now
        expect {
          iut.execute
        }.to raise_error(Timeout::Error, "execution expired")
        after = Time.now
        expect(after - before).to be < 2.1
      rescue IOError => ex
        ignore_tempfile_bug_on_older_rubies(ex)
      end
    end

    it 'should kill the subprocess when a TimeoutError is raised' do
      begin
        test_command = "/bin/sleep"
        test_params = ["2"]
        iut = SHExecutor::Executor.new({:timeout => 1, :wait_for_completion => true, :application_path => test_command, :params => test_params})
        expect(Process).to receive(:kill)
        expect {
          iut.execute
        }.to raise_error(Timeout::Error, "execution expired")
      rescue IOError => ex
        ignore_tempfile_bug_on_older_rubies(ex)
      end
    end

    it 'should call run_process with the command and parameters specified' do
      begin
        test_command = "/bin/ls"
        test_params = ["/tmp/"]
        iut = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => test_command, :params => test_params})
        stdin = stdout = stderr = StringIO.new
        expect(iut).to receive(:run_process).with(test_command, *test_params).and_return([stdout, stderr, Result.new(true)])
        iut.execute
      rescue IOError => ex
        ignore_tempfile_bug_on_older_rubies(ex)
      end
    end

    it 'should use run_process with the command' do
      begin
        test_command = "/bin/ls"
        iut = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => test_command})
        stdin = stdout = stderr = StringIO.new
        expect(iut).to receive(:run_process).with(test_command).and_return([stdout, stderr, Result.new(true)])
        iut.execute
      rescue IOError => ex
        ignore_tempfile_bug_on_older_rubies(ex)
      end
    end

    it 'should block until completion' do
      begin
        test_command = "/bin/sleep"
        test_params = ["2"]
        iut = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => test_command, :params => test_params})
        before = Time.now
        iut.execute
        after = Time.now
        expect(after - before).to be > 2
      rescue IOError => ex
        ignore_tempfile_bug_on_older_rubies(ex)
      end
    end

    it 'should block until completion and still have access to the ouput' do
      begin
        path = temp_file_path("testingargumenterror")
        `echo "sleep 2" >> #{path}`
        `echo "echo 'this did run'" >> #{path}`
        sleep 1
        iut = SHExecutor::Executor.new({:protect_against_injection => false, :wait_for_completion => true, :application_path => path})
        before = Time.now
        iut.execute
        iut.flush
        expect(iut.stdout).to eq("this did run\n")
        after = Time.now
        expect(after - before).to be > 2
      rescue IOError => ex
        ignore_tempfile_bug_on_older_rubies(ex)
      end
    end

    it 'should validate' do
      begin
        iut = SHExecutor::Executor.new({:wait_for_completion => true})
        expect{
          iut.execute
        }.to raise_error(ArgumentError, "No application path provided")

      rescue IOError => ex
        ignore_tempfile_bug_on_older_rubies(ex)
      end
    end
  end

  context 'when asked to redirect stdout to a file appending' do
    before :each do
      @stdout_test_path = '/tmp/append_stdout_path'
      FileUtils.rm_f(@stdout_test_path)
    end

    def execute_stdout_test_command(append = true)
      test_command = "/bin/echo"
      test_params = ["hello world"]
      @iut = SHExecutor::Executor.new({:append_stdout_path => append, :stdout_path => @stdout_test_path, :wait_for_completion => true, :application_path => test_command, :params => test_params})
      @iut.execute
      @iut.flush
      File.open(@stdout_test_path).read
    end

    it 'should append stdout to the file specified, and create it if it does not exist' do
      expect(execute_stdout_test_command).to eq("hello world\n")
    end

    it 'should append stdout to the file specified, if it exists' do
      `echo "line 1" >> #{@stdout_test_path}`
      expect(execute_stdout_test_command).to eq("line 1\nhello world\n")
    end

    it 'should delete if exists and create the specified file, then write to it if append is not set' do
      `echo "line 1" >> #{@stdout_test_path}`
      expect(execute_stdout_test_command(false)).to eq("hello world\n")
    end

    it 'should raise an exception if one of the file operations fails' do
      @stdout_test_path = "/tmp/thisdirectorydoesnotexistdshlgh58iyg89rlehg8y/gn.dfllgyls54gh57479gh"
      error_received = false
      begin
        execute_stdout_test_command
      rescue => ex
        error_received = (ex.class == Errno::ENOENT) and
                         (ex.message.include?("No such file or directory")) and
                         (ex.message.include?("/tmp/thisdirectorydoesnotexistdshlgh58iyg89rlehg8y/gn.dfllgyls54gh57479gh"))
      end
      expect(error_received).to eq(true)
    end
  end

  context 'when asked to redirect stderr to a file appending' do
    before :each do
      @stderr_test_path = '/tmp/append_stderr_path'
      FileUtils.rm_f(@stderr_test_path)
    end

    def execute_stderr_test_command(append = true)
      test_command = "/bin/ls"
      test_params = ["/tmp/thisfiledoesnotexistsatgup80wh0hgoefhgohuo4whg4whg4w5hg0"]
      @iut = SHExecutor::Executor.new({:append_stderr_path => append, :stderr_path => @stderr_test_path, :wait_for_completion => true, :application_path => test_command, :params => test_params})
      @iut.execute
      @iut.flush
      File.open(@stderr_test_path).read
    end

    it 'should append stderr to the file specified, and create it if it does not exist' do
      expect(execute_stderr_test_command.include?("/tmp/thisfiledoesnotexistsatgup80wh0hgoefhgohuo4whg4whg4w5hg0")).to eq(true)
      expect(execute_stderr_test_command.include?("No such file or directory")).to eq(true)
    end

    it 'should append stderr to the file specified, if it exists' do
      `echo "line 1" >> #{@stderr_test_path}`
      expect(execute_stderr_test_command.include?("line 1")).to eq(true)
      expect(execute_stderr_test_command.include?("/tmp/thisfiledoesnotexistsatgup80wh0hgoefhgohuo4whg4whg4w5hg0")).to eq(true)
      expect(execute_stderr_test_command.include?("No such file or directory")).to eq(true)
    end

    it 'should delete if exists and create the specified file, then write to it if append is not set' do
      `echo "line 1" >> #{@stderr_test_path}`
      expect(execute_stderr_test_command(false).include?("/tmp/thisfiledoesnotexistsatgup80wh0hgoefhgohuo4whg4whg4w5hg0")).to eq(true)
      expect(execute_stderr_test_command(false).include?("No such file or directory")).to eq(true)
    end

    it 'should raise an exception if one of the file operations fails' do
      @stderr_test_path = "/tmp/thisdirectorydoesnotexistdshlgh58iyg89rlehg8y/gn.dfllgyls54gh57479gh"
      error_received = false
      begin
        execute_stderr_test_command
      rescue => ex
        error_received = (ex.class == Errno::ENOENT) and
                         (ex.message.include?("No such file or directory")) and
                         (ex.message.include?("/tmp/thisdirectorydoesnotexistdshlgh58iyg89rlehg8y/gn.dfllgyls54gh57479gh"))
      end
      expect(error_received).to eq(true)
    end
  end

  context 'when asked to flush' do
    it 'should flush to its buffer for stderr' do
      test_command = "/bin/echo"
      test_params = ["hello world"]
      iut = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => test_command, :params => test_params})
      iut.execute
      iut.flush
      expect(iut.stdout).to eq("hello world\n")
      expect(iut.stderr).to be_nil
    end

    it 'should flush to its buffer for stdout' do
      test_command = "/bin/ls"
      test_params = ["/tmp/thisfiledoesnotexistsatgup80wh0hgoefhgohuo4whg4whg4w5hg0"]
      iut = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => test_command, :params => test_params})
      iut.execute
      iut.flush
      expect(iut.stdout).to be_nil
      expect(iut.stderr.include?("/tmp/thisfiledoesnotexistsatgup80wh0hgoefhgohuo4whg4whg4w5hg0")).to eq(true)
      expect(iut.stderr.include?("No such file or directory")).to eq(true)
    end
  end
end
