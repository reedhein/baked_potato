class BPImage
  attr_accessor :db_image
  def initialize(image, cache_folder)
    @image    = Pathname.new(image)
    @db_image = DB::ImageProgressRecord.find(opportunity_id: cache_folder.opp_id)
  end

  def lock
    @db_image.update(locked: true)
  end

  def self.random_unlocked
    records = DB::ImageProgressRecord.all(locked: false, complete: false, type: '.pdf') ||
      DB::ImageProgressRecord.all(locked: false, complete: false, type: '.png') ||
      DB::ImageProgressRecord.all(locked: false, complete: false, type: '.jpg')
    record = records.sample
    cf = CacheFolder.new(opp_id: record.opportunity_id)
    path_to_image = Pathname.new([cf.cache_folder, cf.folder, record.filename].join('/'))
    bpi = BPImage.new(path_to_image, cf)
    bpi.db_image = record
    bpi
  end

  def full_path
    @db_image.full_path
  end
end
