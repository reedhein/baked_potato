require_relative 'console_potato'
class CronJob
  attr_reader :cp
  def initialize
    @cm = CloudMigrator.new(environment: :production)
    @worker_pool = WorkerPool.instance
  end

  def remove_old_cache_folder
    cache_folder = cp.dated_cache_folder
    return unless cache_folder.parent.each_child.count > 7
    cache_folder.parent.each_child do |entity|
      if entity.directory? && Date.parse(entity.basename) < (Date.today - 7.days)
        binding.pry
        @worker_pool.tasks.push Proc.new { FileUtils.rm_r(entity) }
      end
    end
    remove_date = (Date.today - 3.days).to_s
    folder_path_to_remove  = cache_folder.parent + remove_date
    @worker_pool.tasks.push Proc.new{ FileUtils.rm_rf(folder_path_to_remove) } if folder_path_to_remove.exist?
  end

  def copy_todays_folder_to_tomorrow
    cache_folder = @cm.dated_cache_folder
    folder_to_copy = cache_folder.parent + Date.today.to_s
    day = 0
    until folder_to_copy.exist? do
      day += 1
      folder_to_copy = cache_folder.parent + (Date.today - day.day).to_s
    end
    destination_folder = (cache_folder.parent + Date.tomorrow.to_s)
    system_call = "rsync -r --ignore-existing #{folder_to_copy.to_s}/ #{destination_folder.to_s}"
    puts system_call
    `#{system_call}`
  end

  def reconcile_box_and_salesforce
    # @cm.browser_tool.authenticate
    @cm.produce_snapshot_from_scratch
  rescue Restforce::UnauthorizedError => e
    ap e.backtrace
    binding.pry
  end

  def reconcile_s_drive
    @cm.sync_s_drive
  end
end

w = WorkerPool.instance
cj = CronJob.new
copy_thread   = Thread.new { cj.copy_todays_folder_to_tomorrow }
remove_thread = Thread.new { cj.remove_old_cache_folder }
(60 * 60).downto(1) do |i|
  puts "allowing copy to get head start"
  puts "time left: #{i}"
  sleep 1
  system('clear')
  if copy_thread.status == false || copy_thread.status.nil?
    puts "copy finished"
    break
  end
end
cj.reconcile_box_and_salesforce
rsync_s_drive = 'rsync -rvz --progress --ignore-existing --delete-after --size-only ~/Sandbox/s_drive/Client\ Management/REED\ HEIN\ and\ ASSOCIATES/_Timeshare\ Exits/ /home/doug/Sandbox/s_drive_exits_backup'
`#{rsync_s_drive}`
cj.reconcile_s_drive
copy_thread.priority = 3
remove_thread.priority = 2
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
