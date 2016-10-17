class Action
  def perform
    fail 'subclass must invoke perform'
  end
end
path = File.dirname(File.absolute_path(__FILE__) )
Dir.glob(path + '/action/*').delete_if{ |file| File.directory?(file) }.each{ |file| require file }
