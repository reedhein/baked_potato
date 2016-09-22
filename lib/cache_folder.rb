class CacheFolder

  def initialize(path)
    @path           = Pathname.new(path)
    @cache_folder   = self.class.path
    @id             = @path.parent.to_s.split('/').last
    @location       = path
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
    @meta ||= YAML.load(File.open(@path.parent + 'meta.yml').read)
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
    @path.children.map{|p| self.class.create_from_path(p)}
  end

  def directory?
    @path.directory?
  end

  def folders
    @path.children.select{ |x| x.directory? }
  end

  def files
    @path.children.select{ |x| x.file? }
  end

end
