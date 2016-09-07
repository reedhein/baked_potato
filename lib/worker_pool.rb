require 'thread'

class WorkerPool
  WAIT_TIMEOUT = 1 # 1 second
  include Singleton
  attr_accessor :tasks, :workers

  def initialize
    @interrupted = false
    @mutex ||= Mutex.new
    # signal handling
    Signal.trap('INT') do
      @interrupted = true
      finish

      exit 0
    end

    @tasks = Queue.new
    @workers = 4.times.map do |i|
      Thread.new do |t|
        begin
          loop do
            wait_for_tasks
            if @tasks.empty? or @interrupted
              break
            end
            @mutex.synchronize do
              x = @tasks.pop(true)
              x.call
            end
          end
        rescue ThreadError => e
          puts e.inspect
          binding.pry
        rescue => e
          puts e.inspect
        end
      end
    end
  end

  def <<(&block)
    @tasks.push block
  end

  def finish
    @workers.map(&:join)
  end

private

  def wait_for_tasks
    while @tasks.length == 0 do
      sleep WAIT_TIMEOUT
    end
    puts 'breaking out'
  end
end
