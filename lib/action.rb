class Action
  attr_accessor :email, :source_id, :destination_id, :rename, :file_id, :box_client, :sf_client
  def initialize(email: nil, source_id: nil, destination_id: nil, rename: nil, file_id: nil)
    @email          = email
    @user           = DB::User.first(email: @email)
    @source_id      = source_id
    @destination_id = destination_id
    @rename         = rename
    @file_id        = file_id
    @record         = DB::ImageProgressRecord.first(@file_id)
    @box_client     = Utils::Box::Client.new(@user)
    @sf_client      = Utils::SalesForce::Client.new(@user)
  end

  def perform
    fail 'subclass must invoke perform'
  end

  def folder_type_by_id(id)
    case id
    when /^500/
      :case
    when /^006/
      :opportunity
    else
      :box
    end
  end

  def file_type_by_id(file_id)
    if file_id =~ /^00P/
      :salesforce
    else
      :box
    end
  end
end
path = File.dirname(File.absolute_path(__FILE__) )
Dir.glob(path + '/action/*').delete_if{ |file| File.directory?(file) }.each{ |file| require file }
