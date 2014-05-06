require 'hutch'
require 'open3'
require 'ostruct' # work around bug in hutch
require 'hutch/logging'
require 'time'

def send
  config = Hutch::Config
  config.set(:mq_host, 'rabbit1')
  config.set(:mq_api_host, 'rabbit1')
  config.set(:mq_api_port, 55672)
  config.set(:mq_vhost, '/')
  config.set(:log_level, Logger::WARN)
  Hutch.connect({}, config)
  bot_name = ARGV.delete_at(0)
  run_id = ARGV.delete_at(0)
  puts "Started bot #{bot_name}, run #{run_id}..."
  count = 0
  command_output_each_line(ARGV.join(" "), {}) do |line|
    line = {data: JSON.parse(line)}
    line[:bot_name] = bot_name
    line[:run_id] = run_id
    line[:export_date] = Time.now.iso8601()
    Hutch.publish('bot.record', line)
    count += 1
  end
  puts "Finished. Wrote #{count} records"
end

def command_output_each_line(command, options={})
  Open3::popen3(command, options) do |_, stdout, stderr, wait_thread|
    loop do
      check_output_with_timeout(stdout)

      begin
        result = stdout.readline.strip
        yield result unless result.empty?
        # add run id and bot name
      rescue EOFError
        break
      end
    end
    status = wait_thread.value.exitstatus
    if status > 0
      message = "Bot <#{command}> exited with status #{status}: #{stderr.read}"
      raise RuntimeError.new(message)
    end
  end
end

def check_output_with_timeout(stdout, initial_interval = 10, timeout = 180)
  interval = initial_interval
  loop do
    reads, _, _ = IO.select([stdout], [], [], interval)
    break if !reads.nil?
    raise "Timeout! - could not read from external bot after #{timeout} seconds" if reads.nil? && interval > timeout
    interval *= 2
  end
end

send()
