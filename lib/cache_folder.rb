class CacheFolder

  attr_reader :path, :id
  def initialize(path)
    @path           = Pathname.new(path)
    @cache_folder   = self.class.path
    @type           = determine_file_or_directory
    @id             = determine_id
    @sf_client      = Utils::SalesForce::Client.instance
    @box_client     = Utils::Box::Client.instance
  end

  def self.root
    self.create_from_path(self.cache_folder)
  end

  def self.path
    RbConfig::CONFIG['host_os'] =~ /darwin/ ? Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder') + Date.today.to_s : Pathname.new('/home/doug/Sandbox/cache_folder' ) + Date.today.to_s
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
    @path.children.select{ |x| x.directory? }.map{|d| CacheFolder.new(d)}
  end

  def files
    @path.children.select{ |x| x.file? }.map{|d| CacheFolder.new(d)}
  end

  private 

  def determine_file_or_directory
    @path.file? ? :file : :directory
  end
  
  def determine_id
    if @type == :file
      @path.parent.to_s.split('/').last
    else
      @path.to_s.split('/').last
    end
  end
end
