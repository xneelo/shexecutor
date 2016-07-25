# SHExecutor

SHExecutor is a convenience wrapper for executing shell commands from with-in a ruby process.

## It supports:
- blocking indefinitely, on exit you can get status, stdout and stderr
- blocking with timeout, on exit you can get status, stdout, stderr, timeout exception (then output streams are not available)
- non-blocking, then you get handles to the output streams and the status of the forked process
- replacement, then you get a replaced process and none of the above
- redirecting of stderr and stdout, separately, to file, with the option to overwrite or append

## It does not support:
- streaming input to stdin
- being nested in an outer Timeout (see 'complications' below)

## For any executor:
- you can ask status, which will tell you "not executed", current status (e.g. run or sleep) and "no longer executing"
- you can ask result, which gives you nil unless the process is no longer executing, in which case you get status (e.g. pid, exit code, sigints.)

For a full description of status, please see Process::Status

This gem is sponsored by Hetzner (Pty) Ltd - http://hetzner.co.za

## Initialization options:

Required / optional:

```
  {
    :application_path                     # Path of the command to run
    :params                               # Parameters to pass the command
  }
```

```
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
```

## Installation

Add this line to your application's Gemfile:

    gem 'shexecutor'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install shexecutor

##Module helpers

###Blocking

```
result, stdout, stderr = ::SHExecutor::execute_blocking("/bin/ls", "/tmp/")
```

###Blocking with timeout

```
result, stdout, stderr = ::SHExecutor::execute_and_timeout_after("/bin/sleep", "10", 2)
```

###Non-blocking

```
thr, stdout_io, stderr_io = ::SHExecutor::execute_non_blocking("/bin/sleep", "20")
```

##Executor API

###Blocking

```
iut = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => "/bin/echo", :params => ["hello world"]})
result = iut.execute
iut.flush
puts "After execution status is: #{iut.status}"
# "no longer executing"
puts "out: #{iut.stdout} err: #{iut.stderr}"
puts "#{result.pid} success? #{result.success?} with code #{result.exitstatus}"
puts "For more see: #{iut.result.methods}"
```

###Blocking with timeout

```
iut = SHExecutor::Executor.new({:timeout => 1, :wait_for_completion => true, :application_path => "/bin/sleep", :params => ["2"]})
result = iut.execute
# Timeout::Error gets raised. The spawned process is killed with TERM, and then with signal 9 if it does not close in timeout_sig_kill_retry ms
```

###Non-blocking

```
iut = SHExecutor::Executor.new({:wait_for_completion => false, :application_path => "/bin/sleep", :params => ["1"]})
stdout, stderr, thr = iut.execute
puts "Status: #{iut.status}"
puts "PID: #{thr.pid}"
# "run" or "sleep"
sleep 2
puts "Status: #{iut.status}"
# "no longer executing"
```

###Replacing

```
iut = SHExecutor::Executor.new({:replace => true, :application_path => "/bin/echo", :params => ["Your process has been assimilated"]})
iut.execute
```

###stdout and stderr

```
iut.flush
puts iut.stdout
puts iut.stderr
```

###redirecting stdout and stderr
```
iut = SHExecutor::Executor.new({:wait_for_completion => true, :application_path => "/bin/echo", :params => ["this is stdoutin a file"], :stdout_path => "/tmp/mystdout", :stderr_path => "/tmp/mystderr", :append_stdout_path => false, :append_stderr_path => true})
iut.execute
iut.flush
puts iut.stdout
puts iut.stderr
```

## Complications
  Remember to call iut.flush in order to access stdout and stderr in the Executor object.

  Nested timeouts can result in complications. Because Executor drains stdout and stderr to avoid dead-locking, these StringIO streams will raise an IOError if they are interrupted. The backtrace of these IOErrors will not contain information of an outer Timeout or other exception that interrupted the Executor. The code below illustrates the complication:

```
def shexecutor_complication
  result, stdout, stderr = ::SHExecutor::execute_and_timeout_after("/bin/sleep", "30", 20)
end

Timeout::timeout(5) do
  shexecutor_complication
end

# shexecutor.rb:in 'copy_stream': stream closed (IOError)
```

## Contributing

  Please send feedback and comments to the author at:

  Ernst van Graan <ernstvangraan@gmail.com>

  Thanks to Sheldon Hearn for review and great ideas that unblocked complex challenges (https://rubygems.org/profiles/sheldonh).
