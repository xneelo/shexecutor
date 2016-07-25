require "shexecutor/version"
require 'open3'

module SHExecutor
  @@default_options = {
    :timeout => -1,                     # Seconds after which to raise Timeout::Error if not completed
    :protect_against_injection => true, # look for spaces in and tainted application path
    :stdout_path => nil,                # file to append stdout to
    :stderr_path => nil,                # file to append stderr to
    :append_stdout_path => true,        # if true, will append, otherwise will overwrite
    :append_stderr_path => true,        # if true, will append, otherwise will overwrite
    :replace => false,                  # replace the running process with the command
    :wait_for_completion => false,      # block until the command completes
    :timeout_sig_kill_retry => 500      # if timeout occurs, send TERM, and send signal 9 if still present after X ms
  }

  def self.default_options
    @@default_options
  end

  def self.execute_blocking(application_path, params = nil)
    executor = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => application_path, :params => params})
    result = executor.execute
    executor.flush
    return result, executor.stdout, executor.stderr
  end

  def self.execute_and_timeout_after(application_path, params = nil, timeout = -1)
    executor = SHExecutor::Executor.new({:timeout => timeout, :wait_for_completion => true, :application_path => application_path, :params => params})
    result = executor.execute
    executor.flush
    return result, executor.stdout, executor.stderr
  end

  def self.execute_non_blocking(application_path, params = nil)
      executor = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => application_path, :params => params})
     executor.execute
  end

  class Executor
    public

    attr_accessor :stdout
    attr_accessor :stderr
    attr_accessor :options

    private
    
    attr_accessor :result
    attr_accessor :pid
    attr_accessor :data_out
    attr_accessor :data_err

    public

    def initialize(options = ::SHExecutor::default_options)
      # set default options
      @options = ::SHExecutor::default_options.dup

      # then apply specified options
      options.each do |key, value|
        @options[key] = value
      end

      @options
    end

    def status
      return "not executed" if @result.nil?
      return @result.status if @result.alive?
      return "no longer executing" if not @result.alive?
    end

    def result
      return nil if status != "no longer executing"
      @result.value
    end

    def validate
      errors = []
      if (@options[:protect_against_injection]) and (!@options[:application_path].nil? and @options[:application_path].strip != "")
        if (File.exists?(@options[:application_path]))
          errors << "Application path not executable" if !File.executable?(@options[:application_path])
	else
          errors << "Application path not found"
	end

       errors << "Suspected injection vulnerability due to space in application_path or the object being marked as 'tainted' by Ruby. Turn off strict checking if you are sure by setting :protect_against_injection to false" if possible_injection?(@options[:application_path])

      else
        errors << "No application path provided" if (@options[:application_path].nil?) or (@options[:application_path].strip == "")
      end

      raise ArgumentError.new(errors.join(',')) if errors.count > 0
    end

    def execute
      @pid = nil
      @stdout = nil
      @stderr = nil
      if (@options[:replace] == true)
        replace_process
      else
        if (@options[:wait_for_completion])
          if (@options[:timeout] <= 0)
            block_process
          else
            block_process_with_timeout
          end
        else
          fork_process
        end
      end
    end

    def flush
      return nil if @data_out.nil? or @data_err.nil?
      stdout_data = @data_out.string
      stderr_data = @data_err.string
      @stdout = stdout_data if stdout_data != ""
      @stderr = stderr_data if stderr_data != ""
      stdout_to_file if (@options[:stdout_path])
      stderr_to_file if (@options[:stderr_path])
    end

    private

    def possible_injection?(application_path)
      (@options[:protect_against_injection]) and (@options[:application_path].include?(" ") or @options[:application_path].tainted?)
    end

    def buffer_to_file(buffer, path, append)
      if not append
        FileUtils.rm_f(path)
      end
      File.write(path, buffer, buffer.size, mode: 'a')
    end

    def stdout_to_file
      buffer_to_file(@data_out.string, @options[:stdout_path], @options[:append_stdout_path]) if @options[:stdout_path]
    end

    def stderr_to_file
      buffer_to_file(@data_err.string, @options[:stderr_path], @options[:append_stderr_path]) if @options[:stderr_path]
    end

    def replace_process
      validate
      @options[:params].nil? ? exec(@options[:application_path]) : exec(@options[:application_path], *@options[:params]) 
    end

    def run_process(application_path, options = "")
      data_out = StringIO.new
      data_err = StringIO.new
      @t0 = nil
      Open3::popen3(application_path, options) do |stdin, stdout, stderr, thr|
        @t0 = thr
        t1 = Thread.new do
          begin
            IO.copy_stream(stdout, data_out)
          rescue Exception => ex
            raise TimeoutError.new("execution expired") if @timeout_error
            raise ex
          end
        end
        t2 = Thread.new do
          begin
            IO.copy_stream(stderr, data_err)
          rescue Exception => ex
            raise TimeoutError.new("execution expired") if @timeout_error
            raise ex
          end
        end
        m = Mutex.new
        done = false
        timedout = false
        t3 = Thread.new do
          count = 0
          while (count < @options[:timeout]*10) and (@t0.alive?) do
            sleep 0.1
            count = count + 1
          end
          m.synchronize do
            if count >= @options[:timeout]*10
              timedout = true
            end
            done = true
          end
        end if should_timeout?
        stdin.close
        t1.abort_on_exception = true if should_timeout?
        t2.abort_on_exception = true if should_timeout?
        t3.abort_on_exception = true if should_timeout?
        t1.join if not should_timeout?
        t2.join if not should_timeout?
        if should_timeout?
          d = false
          m.synchronize do
            d = done
          end
          while not d do
            sleep 0.1
            m.synchronize do
              d = done
            end
          end

          if not timedout
            t1.join 
            t2.join
            t3.join
          else
            @timeout_error = true
          end
        end
      end
      return data_out, data_err, @t0
    end

    def block_process
      validate
      @data_out, @data_err, @result = run_process(@options[:application_path], *@options[:params])
      @result.join
      @result.value
    end

    def block_process_with_timeout
      validate
      begin
        @data_out, @data_err, @result = run_process(@options[:application_path], *@options[:params])
        raise Timeout::Error.new("execution expired") if @timeout_error
        @result.join
        @result.value
      rescue Timeout::Error => ex
        kill_process(@t0.pid)
        raise ex
      end
    end

    def process?(pid)
      begin
        Process.getpgid(pid)
        true
      rescue Errno::ESRCH
        false
      end
    end

    def kill_process(pid)
      return if pid.nil?
      Process.kill("TERM", pid)
      count = 0
      while (count < (@options[:timeout_sig_kill_retry]/100) and process?(pid)) do
        sleep 0.1
      end
      Process.kill(9, pid) if process?(pid)
    rescue Errno::ESRCH
      #done
    end

    def fork_process
      validate
      @stdin_stream, @stdout_stream, @stderr_stream, @result = Open3::popen3(@options[:application_path], *@options[:params]) 
      return @result, @stdout_stream, @stderr_stream
    end

    def should_timeout?
      @options[:timeout] > 0
    end
  end
end
