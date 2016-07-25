module Kernel
  @@last_command = nil
  @@last_params = nil

  def exec(cmd, params = nil)
    @@last_command = cmd
    @@last_params = params
    puts "Kernel::exec('#{cmd}', '#{params}')"
  end

  def last_command=(command)
    @@last_command = command
  end

  def last_command
    @@last_command
  end

  def last_params
    @@last_params
  end
end
