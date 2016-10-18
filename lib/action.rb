class Action
  attr_accessor :email, :source_id, :destination_id, :rename, :file_id, :box_client, :sf_client
  def initialize(email: nil, source_id: nil, destination_id: nil, rename: nil, file_id: nil)
    @email          = email
    @user           = DB::User.first(email: @email)
    @source_id      = source_id
    @destination_id = destination_id
    @rename         = rename
    @file_id        = file_id
    @record         = get_record 
    @box_client     = Utils::Box::Client.new(@user)
    @sf_client      = Utils::SalesForce::Client.new(@user)
  end

  def perform
    fail 'subclass must invoke perform'
  end

  def get_record
    records = DB::ImageProgressRecord.all(file_id: @file_id)
    latest_record = nil
    if records.count > 1 && records.map(&:sha1).uniq.count == 1
      latest_record = records.sort_by{|r| Date.parse(r.date)}.last
      records.each{|r| r.destroy unless r == latest_record}
    end
    binding.pry unless latest_record || records.first
    latest_record || records.first
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
