class CacheFolder

  def initialize(id)
    @cache_folder   = Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder') + Date.today.to_s
    @id             = id
    @location       = find_location_by_id
    @path           = Pathname.new(@location)
    @sf_client      = Utils::SalesForce::Client.instance
    @box_client     = Utils::Box::Client.instance
  end

  def self.root
    self.create_from_path(self.cache_folder)
  end

  def type
    @type ||= get_type
  end

  def to_s
    @path.try(:to_s)
  end

  def location
    @location ||= find_location_by_id
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

  def files
    begin
      self.children.select{|x| binding.pry;x.file?}
    rescue
      binding.pry
    end
  end

  def file?
    @path.file?
  end

  def folders
    self.path.children.select{ |x| x.directory? }
  end

  def +(path)
    @path + path
  end

  def path
    @path ||= Pathname.new(@location)
    binding.pry unless @path
    @path
  end

  def self.opp_id_from_path(path)
    path = Pathname.new(path)
    case path
    when path.file?
      path
    when path.split.last.to_s.match(/\d+_.+_\d+/).present?
      path.split.last.to_s.split('_')[1]
    when path.split.last.to_s.match(/^(500|006)/).present? && path.split.last.to_s.size == 18
      path.split.last.to_s
    when path.split.last.to_s.match( /^\d{11}$/ ).present?
      deliminator.split.last.to_s
    end
  end

  def self.create_from_path(path)
    path = Pathname.new(path)
    if path.file?
      path
    elsif path.split.last.to_s.match(/\d+_.+_\d+/).present?
      id = path.split.last.to_s.split('_')[1]
      self.new(id)
    elsif path.split.last.to_s.match(/^(500|006)/).present? && path.split.last.to_s.size == 18
      id = path.split.last.to_s
      self.new(id)
    elsif path.split.last.to_s.match( /^\d{11}$/ ).present?
      id = deliminator.split.last.to_s
      self.new(id)
    else
      path
    end
  end

  def self.find_location_by_id(id)
    directory = Dir.glob(self.cache_folder + '**/*').detect do |entity|
      e = Pathname.new(entity)
      e.directory? && e.split.last.to_s == id
    end
    directory
  end

  private

  def find_location_by_id
    fail 'no id provided' unless @id
    directory = Dir.glob(@cache_folder + '**/*').detect do |entity|
      e = Pathname.new(entity)
      e.directory? && e.split.last.to_s == @id
    end
    binding.pry unless directory
    directory
  end

  def process_deliminator(deliminator)
    case deliminator
    when String
      if Pathname.new(deliminator).file?
        @id = deliminator.to_s
      else
        @id = deliminator
      end
    when Pathname
      if deliminator.file?
        @id = deliminator.to_s
      elsif deliminator.split.last.to_s =~ /\d+_.+_\d+/
        @id = deliminator.split.last.to_s.split('_')[1]
      elsif deliminator.split.last.to_s =~ /^(500|006)/ && deliminator.split.last.to_s.size == 18
        @id = deliminator.split.last.to_s
      elsif deliminator.split.last.to_s =~ /^\d{11}$/
        @id = deliminator.split.last.to_s
      else
        @id = deliminator.to_s
      end
    when NewCacheFolder, OldCacheFolder
      @id = deliminator.id.to_s
    end
  end

end
