require_relative 'console_potato'
class CronJob

  def remove_old_cache_folder
    cp = ConsolePotato.new(environment: :production)
    cache_folder = cp.dated_cache_folder
    remove_date = (Date.today - 3.days).to_s
    folder_path_to_remove  = cache_folder.parent + remove_date
    FileUtils.rm_r(folder_path_to_remove) if folder_path_to_remove.exist?
  end

  def copy_todays_folder_to_tomorrow
    cp = ConsolePotato.new(environment: :production)
    cache_folder = cp.dated_cache_folder
    folder_to_copy = cache_folder.parent + Date.today.to_s
    day = 0
    until folder_to_copy.exist? do
      binding.pry
      day += 1
      folder_to_copy = cache_folder.parent + (Date.today - day.day).to_s
    end
    destination_folder = cache_folder.parent + Date.tomorrow.to_s
    FileUtils.cp_r(folder_to_copy, destination_folder)
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

cj = CronJob.new
cj.remove_old_cache_folder
cj.copy_todays_folder_to_tomorrow
cj.reconcile_box_and_salesforce
cj.reconcile_s_drive
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
