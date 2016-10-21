require_relative 'console_potato'
class CronJob

  def remove_old_cache_folder
    cp = ConsolePotato.new(environment: :production)
    cache_folder = cp.dated_cache_folder
    remove_date = Date.today - 3.days
    folder_path_to_remove  = cache_folder + remove_date
    binding.pry
    FileUtils.rm_r(folder_path_to_remove)
  end

  def reconcile_box_and_salesforce
    cp = ConsolePotato.new(environment: :production)
    cp.produce_snapshot_from_scratch
  end

  def reconcile_s_drive
    cp = ConsolePotato
    cp.sync_s_drive
  end

end

w = WorkerPool.instance
count = w.tasks.size
kill_switch = 0
while w.tasks.size > 1 do
  sleep 1
  new_count = w.tasks.size
  if new_count == count
    kill_switch += 1
    puts 'kill switch at ' + kill_switch.to_s if kill_switch > 10
  else
    count = new_count
    kill_switch = 0
  end
  binding.pry if kill_switch > 60*5
  puts '\''*88
  puts "task size: #{w.tasks.size}"
  puts '\''*88
end
  # cp.browser_tool.agents.each(&:close)
