class CacheFolder

  attr_reader :path, :id, :file_id
  def initialize(path)
    binding.pry if path.nil?
    @path           = Pathname.new(path)
    @cache_folder   = self.class.path
    @type           = determine_file_or_directory
  end

  def self.root
    self.create_from_path(self.cache_folder)
  end

  def self.path
    RbConfig::CONFIG['host_os'] =~ /darwin/ ? Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder') + Date.today.to_s : Pathname.new('/home/doug/Sandbox/dated_cache_folder' ) + Date.today.to_s
  end

  def self.smb_path
    RbConfig::CONFIG['host_os'] =~ /darwin/ ? Pathname.new('/Users/voodoologic/Sandbox/s_drive_exits_backup')  : Pathname.new('/home/doug/Sandbox/s_drive_exits_backup' )
  end

  def self.find_by_id(id)
    record = DB::ImageProgressRecord.first(parent_id: id)
    new(record.full_path.parent)
  end

  def self.find_from_record(record, type = :salesforce)
    if type == :salesforce
      id = record.sales_force_id
    else
      id = record.box_id
    end
    path = folder_by_id(id)
    binding.pry unless path
    CacheFolder.new(path)
  end

  def file_id
    id
  end

  def id
    @id || determine_id
  end

  def move_to_folder_id(id)
    dest_path = self.class.folder_by_id(id)
    FileUtils.mv(@path, dest_path)
  rescue => e
    ap e.backtrace
    binding.pry
  end

  def renmae(name)
    @path.rename(name)
  end

  def meta
    @meta ||= determin_meta
  end

  def name
    meta[:name]
  end

  def cloud_path
    parent_type.to_s + '/' + @path.parent.basename.to_s
  end

  def sha1
    BPImage.new(self).db.sha1 if type == :file
  end

  def filename
    BPImage.new(self).db.filename if type == :file
  end

  def determin_meta
    if parent_type == :box
      box_parent_db
    else
      salesforce_parent_db
    end
  end

  def salesforce_parent_db(_path = nil)
    path = _path || @path
    parent = path.ascend.detect do |entity|
      entity.directory? && entity.basename.to_s =~ /^(500|006)/
    end
    DB::SalesForceProgressRecord.first(sales_force_id: parent.basename)
  end

  def box_parent_db(_path = nil)
    path = _path || @path
    parent = path.ascend.detect do |entity|
      entity.directory? && entity.basename.to_s =~ /\d{10,}/
    end
    DB::BoxFolder.first(box_id: parent.basename.to_s) || Utils::Box::Client.new.folder(parent.basename.to_s).storage_object
  end

  def opportunity
    opp_path = @path.ascend.detect do |entity|
      binding.pry unless entity.exist?
      entity.directory? && entity.basename.to_s =~ /^006/
    end
    binding.pry unless opp_path
    CacheFolder.new(opp_path)
  end

  def cases
    cases_folder = @path + 'cases'
    return [] unless cases_folder.exist?
    _cases = cases_folder.children.select do |entity|
      entity.directory? && entity.basename.to_s =~ /^500/
    end
    _cases.map do |case_folder|
      CacheFolder.new(case_folder)
    end
  end

  def box_folders
    #find box folders underneath parent folder
    if @type == :directory
      box_folder = @path.children.detect{|c| c.directory? && c.basename.to_s =~ /\d{10,}/}
    else
      box_folder = @path.parent.children.detect{|c| c.directory? && c.basename.to_s =~ /\d{10,}/}
    end
    if box_folder
      CacheFolder.new(box_folder).folders
    else
      []
    end
  rescue => e
    binding.pry
  end

  def self.parent_type(path)
    id =  @path.parent.basename.to_s
    folder_type_by_id(id)
  end

  def parent_type
    id =  @path.parent.basename.to_s
    self.class.folder_type_by_id(id)
  end

  def self.folder_type_by_id(id)
    case id
    when /^(500|006)/
      :salesforce
    when /\d{10,}/
      :box
    end
  end
  def type
    @type ||= get_type
  end

  def images
    @images ||= get_images
  end

  def mkpath
    @path.mkpath
  end

  def children
    @path.children
  end

  def directory?
    @path.directory?
  end

  def folders
    @path.children.select(&:directory?).map{|d| CacheFolder.new(d)}
  end

  def files
    relevant_children(@path).select(&:file?).map{|d| CacheFolder.new(d)}
  end

  private 

  def self.folder_by_id(id)
    dest_path   = DB::ImageProgressRecord.first(parent_id: id)
    dest_path ||= Find.find(path).with_index do |path,i|
      return Pathname.new(path) if Pathname.new(path).basename.to_s == id
      Find.prune if id.match(/^006/) && i != 0
    end
    dest_path = dest_path.full_path.parent if dest_path.is_a? DB::ImageProgressRecord
  end

  def relevant_children(path)
    path.each_child.select do |entity|
      entity.basename.to_s != 'meta.yml' && entity.basename.to_s != '.DS_Store'
    end
  end

  def determine_file_or_directory
    @path.file? ? :file : :directory
  end

  def determine_id
    if @type == :file
      # @path.parent.to_s.split('/').last
      BPImage.id_from_path(@path) || BPImage.find_id_from_interwebs(@path)
    else
      @path.to_s.split('/').last
    end
  end
end
