class CacheFolder

  attr_reader :path, :id, :file_id
  def initialize(path)
    @path           = Pathname.new(path)
    @cache_folder   = self.class.path
    @type           = determine_file_or_directory
  end

  def self.root
    self.create_from_path(self.cache_folder)
  end

  def self.path
    RbConfig::CONFIG['host_os'] =~ /darwin/ ? Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder') + Date.today.to_s : Pathname.new('/home/doug/Sandbox/cache_folder' ) + Date.today.to_s
  end

  def file_id
    id
  end

  def id
    @id || determine_id
  end

  def move_to_folder_id(id)
    record = DB::ImageProgressRecord.first(parent_id: id)
    FileUtils.mv(path, record.full_path.parent)
  rescue => e
    ap e.backtrace
    binding.pry
  end

  def renmae(name)
    @path.rename(name)
  end

  def meta
    if @type == :directory
      @meta ||= YAML.load(File.open(@path + 'meta.yml').read)
    else
      @meta ||= YAML.load(File.open(@path.parent + 'meta.yml').read)
    end
  end

  def opportunity
    opp_path = @path.ascend.detect do |entity|
      entity.directory? && entity.basename.to_s =~ /^006/
    end
    CacheFolder.new(opp_path)
  end

  def box_folders
    #find box folders underneath parent folder
    if @type == :directory
      CacheFolder.new(@path.children.detect{|c| c.directory? && c.basename.to_s =~ /\d{10,}/}).folders
    else
      CacheFolder.new(@path.parent.children.detect{|c| c.directory? && c.basename.to_s =~ /\d{10,}/}).folders
    end
  end

  def self.parent_type(path)
    case path.parent.basename.to_s
    when /^(500|006)/
      :salesforce
    when /\d{10,}/
      :box
    end
  end

  def parent_type
    case @path.parent.basename.to_s
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
