require 'thread'

class WorkerPool
  WAIT_TIMEOUT = 0.1 # 1 tenth second
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
            puts 'found task'
            if @tasks.empty? or @interrupted
              break
            end
            @mutex.synchronize do
              x = @tasks.pop(true)
              x.call
            end
          end
        rescue ThreadError => e
          ap e.backtrace
          puts e.inspect
          sleep 5
          binding.pry
        rescue => e
          ap e.backtrace
          sleep 5
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
    while @tasks.length < 1 do
      sleep WAIT_TIMEOUT
    end
    puts @workers.inspect
  end
end
