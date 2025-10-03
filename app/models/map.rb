require 'open3'
require 'csv'

class Map < ActiveRecord::Base
  include ErrorCalculator

  NON_FATAL_GDAL_WARNING_PATTERNS = [
    /Warning 1: INIT_DEST was set to NO_DATA, but a NoData value was not defined/i,
    /\A\[\]\z/
  ].freeze

  has_many :gcps, dependent: :destroy
  has_many :layers_maps, dependent: :destroy
  has_many :layers, through: :layers_maps # ,:after_add, :after_remove
  has_many :my_maps, dependent: :destroy
  has_many :users, through: :my_maps
  belongs_to :owner, class_name: 'User'
  belongs_to :import, optional: true

  has_attached_file :upload, styles: { thumb: ['100x100>', :png] },
                             url: '/:attachment/:id/:style/:basename.:extension',
                             default_url: 'missing.png',
                             restricted_characters: %r{[&$+,/:;=?@<>\[\]{})('"|\\\^~%# ]}
  validates_attachment_size(:upload, less_than: MAX_ATTACHMENT_SIZE) if defined?(MAX_ATTACHMENT_SIZE)
  # attr_protected :upload_file_name, :upload_content_type, :upload_size
  validates_attachment_content_type :upload,
                                    content_type: ['image/jpg', 'image/jpeg', 'image/pjpeg', 'image/png',
                                                   'image/x-png', 'image/gif', 'image/tiff']

  validates :title, presence: true
  validates :rough_lat, :rough_lon, :rough_zoom, numericality: { allow_nil: true }
  validates :metadata_lat, :metadata_lon, numericality: { allow_nil: true }
  validates :issue_year, length: { maximum: 4, allow_blank: true }
  validates :issue_year, numericality: { if: proc { |c| c.issue_year.present? } }
  validates :date_depicted, length: { maximum: 4, allow_blank: true }
  validates :date_depicted, numericality: { if: proc { |c| c.date_depicted.present? } }
  validates :unique_id, uniqueness: { allow_blank: true }
  validate :unique_filename, on: :create

  acts_as_taggable
  # acts_as_commentable
  acts_as_enum :map_type, %i[index is_map not_map]
  acts_as_enum :status, %i[unloaded loading available warping warped published]
  acts_as_enum :mask_status, %i[unmasked masking masked]
  acts_as_enum :rough_state, %i[step_1 step_2 step_3 step_4]
  audited allow_mass_assignment: true

  include PgSearch::Model

  multisearchable against: %i[title description], if: :warped_published_and_public?

  scope :warped, lambda {
    where({ status: [Map.status(:warped), Map.status(:published)], map_type: Map.map_type(:is_map) })
  }
  scope :published, -> { where({ status: Map.status(:published), map_type: Map.map_type(:is_map) }) }
  scope :unpublished, -> { where.not(status: Map.status(:published)) }
  scope :are_public, -> { where(public: true) }
  scope :real_maps, -> { where({ map_type: Map.map_type(:is_map) }) }
  scope :unprotected,  -> { unpublished.where(protect: false) }

  attr_accessor :error, :upload_url

  after_initialize :default_values
  before_create :download_remote_image, if: :upload_url_provided?
  before_create :save_dimensions
  after_create :setup_image
  after_create :update_user_counts
  after_destroy :delete_images
  after_destroy :delete_map, :update_counter_cache, :update_layers
  after_destroy :update_user_counts
  after_save :update_counter_cache

  ##################
  # CALLBACKS / Validations
  ###################

  def default_values
    self.status ||= :unloaded
    self.mask_status ||= :unmasked
    self.map_type ||= :is_map
    self.rough_state ||= :step_1
  end

  def unique_filename
    return unless upload.original_filename

    errors.add(:filename, :filename_not_unique) if Map.find_by_upload_file_name(upload.original_filename)
  end

  def upload_url_provided?
    upload_url.present?
  end

  def download_remote_image
    img_upload = do_download_remote_image
    unless img_upload
      errors.add(:upload_url, :error_url) # (en.activerecord.errors.models.map.error_url)
      return false
    end
    self.upload = img_upload

    self.source_uri = (source_uri.presence || upload_url)

    return unless Map.find_by_source_uri(upload_url)

    errors.add(:filename, :filename_not_unique)
    false
  end

  def do_download_remote_image
    io = open(URI.parse(upload_url))
    def io.original_filename
      filename = base_uri.path.split('/').last

      if filename.present?
        basename = File.basename(filename, File.extname(filename)) + '_' + ('a'..'z').to_a.sample(8).join
        extname = File.extname(filename)
        filename = basename + extname
      end

      filename
    end
    io.original_filename.blank? ? nil : io
  rescue StandardError => e
    logger.debug 'Error with URL upload'
    logger.debug e
    false
  end

  def save_dimensions
    if ['image/jp2', 'image/jpeg', 'image/tiff', 'image/png', 'image/gif',
        'image/bmp'].include?(upload.content_type.to_s)
      tempfile = upload.queued_for_write[:original]
      unless tempfile.nil?
        geometry = Paperclip::Geometry.from_file(tempfile)
        self.width = geometry.width.to_i
        self.height = geometry.height.to_i
      end
    end
    self.status = :available
  end

  # this gets the upload, detects what it is, and converts to a tif, if necessary.
  # Although an uploaded tif with existing geo fields may confuse things
  def setup_image
    logger.info 'setup_image '
    self.filename = upload.original_filename
    save!
    if upload?

      if defined?(MAX_DIMENSION) && (width > MAX_DIMENSION || height > MAX_DIMENSION)
        logger.info 'Image is too big, so going to resize '
        if width > height
          dest_width = MAX_DIMENSION
          dest_height = (dest_width.to_f / width.to_f) * height.to_f
        else
          dest_height = MAX_DIMENSION
          dest_width = (dest_height.to_f / height.to_f) * width.to_f
        end
        self.width = dest_width
        self.height = dest_height
        save!
        outsize = ['-outsize', dest_width.to_i, dest_height.to_i]
      else
        outsize = []
      end

      orig_ext = File.extname(upload_file_name).to_s.downcase

      tiffed_filename = ['.tif', '.tiff'].include?(orig_ext) ? upload_file_name : upload_file_name + '.tif'
      tiffed_file_path = File.join(maps_dir, tiffed_filename)

      logger.info 'We convert to tiff'

      # for those greyscale or black and white images with one band
      bands = []
      if raster_bands_count(upload.path) == 1
        if has_palette_colortable?(upload.path)
          bands = ['-expand', 'rgb']
        else
          # if it has one band and grey scale, we need to convert e.g convert grey1band.jpg -type TrueColor  rgb3band.jpg
          command = ['mogrify', '-type', 'TrueColor', upload.path]
          logger.info command
          _, c_stdout, c_stderr = Open3.popen3(*command)

          c_out = c_stdout.readlines.to_s
          c_err = c_stderr.readlines.to_s
          if c_stderr.readlines.empty? && c_err.size > 0
            logger.error 'Error with convert one band script ' + c_err.inspect
            logger.error 'output = ' + c_out
          end

        end
      end

      # transparent pngs may cause issues, so let's remove the alpha band
      bands = ['-b', '1', '-b', '2', '-b', '3'] if raster_bands_count(upload.path) == 4 && orig_ext == '.png'

      command = ["#{GDAL_PATH}gdal_translate", upload.path, outsize, bands, '-co', 'COMPRESS=DEFLATE', '-co',
                 'PHOTOMETRIC=RGB', '-co', 'PROFILE=BASELINE', tiffed_file_path].reject(&:empty?).flatten
      logger.info command
      _, ti_stdout, ti_stderr = Open3.popen3(*command)
      logger.info ti_stdout.readlines.to_s
      logger.info ti_stderr.readlines.to_s

      command = ["#{GDAL_PATH}gdaladdo", '-r', 'average', tiffed_file_path, '2', '4', '8', '16', '32', '64']
      _, o_stdout, o_stderr = Open3.popen3(*command)
      logger.info command

      o_out = o_stdout.readlines.to_s
      o_err = o_stderr.readlines.to_s
      if o_stderr.readlines.empty? && o_err.size > 0
        logger.error 'Error gdal overview script' + o_err.inspect
        logger.error 'output = ' + o_out
      end

      self.filename = tiffed_filename

      # now delete the original
      logger.debug "Deleting uploaded file, now it's a usable tif"
      if File.exist?(upload.path)
        logger.debug 'deleted uploaded file'
        File.delete(upload.path)
      end

    end
    self.map_type = :is_map
    self.rough_state = :step_1
    save!
  end

  # paperclip plugin deletes the images when model is destroyed
  def delete_images
    logger.info 'Deleting map images'
    if File.exist?(temp_filename)
      logger.info 'deleted temp'
      File.delete(temp_filename)
    end
    if File.exist?(warped_filename)
      logger.info 'Deleted Map warped'
      File.delete(warped_filename)
    end
    if File.exist?(warped_overviews_filename)
      logger.info 'Deleted external warped overviews file'
      File.delete(warped_overviews_filename)
    end
    if File.exist?(warped_png_filename)
      logger.info 'deleted warped png'
      File.delete(warped_png_filename)
    end
    if File.exist?(unwarped_filename)
      logger.info 'deleting unwarped'
      File.delete unwarped_filename
    end
    return unless File.exist?(masked_src_filename)

    logger.info 'deleting unwarped masked file'
    File.delete masked_src_filename
  end

  def delete_map
    logger.info 'Deleting mapfile'
  end

  def update_layer
    return if layers.empty?

    layers.each do |layer|
      layer.update_layer
    end
  end

  def update_layers
    logger.debug 'updating (visible) layers'
    return if layers.visible.empty?

    layers.visible.each do |layer|
      layer.update_layer
    end
  end

  def update_counter_cache
    logger.debug 'update_counter_cache'
    return if layers.empty?

    layers.each do |layer|
      layer.update_counts
    end
  end

  def update_gcp_touched_at
    touch(:gcp_touched_at)
  end

  def update_user_counts
    logger.debug 'updating owner map counts'
    return unless owner

    owner.update_map_counts
  end

  # method to publish the map
  # sets status to published
  def publish
    self.status = :published
    save
  end

  # unpublishes a map, sets it's status to warped
  def unpublish
    self.status = :warped
    save
  end

  #############################################
  # CLASS METHODS
  #############################################

  def self.map_type_hash
    values = Map::MAP_TYPE
    keys = [I18n.t('maps.model.map_type.index'), I18n.t('maps.model.map_type.map'),
            I18n.t('maps.model.map_type.not_map')]
    Hash[*keys.zip(values).flatten]
  end

  def self.max_attachment_size
    defined?(MAX_ATTACHMENT_SIZE) ? MAX_ATTACHMENT_SIZE : nil
  end

  def self.max_dimension
    defined?(MAX_DIMENSION) ? MAX_DIMENSION : nil
  end

  #############################################
  # ACCESSOR METHODS
  #############################################

  def maps_dir
    defined?(SRC_MAPS_DIR) ? SRC_MAPS_DIR : Rails.public_path.join('mapimages/src/').to_s
  end

  def dest_dir
    defined?(DST_MAPS_DIR) ? DST_MAPS_DIR : Rails.public_path.join('mapimages/dst/').to_s
  end

  def warped_dir
    dest_dir
  end

  def unwarped_filename
    if filename
      File.join(maps_dir, filename)
    else
      ''
    end
  end

  def warped_filename
    File.join(warped_dir, id.to_s) + '.tif'
  end

  def warped_overviews_filename
    File.join(warped_dir, id.to_s) + '.aux'
  end

  def warped_png_dir
    File.join(dest_dir, '/png/')
  end

  def warped_png
    convert_to_png unless File.exist?(warped_png_filename)
    warped_png_filename
  end

  def warped_png_filename
    File.join(warped_png_dir, id.to_s) + '.png'
  end

  def warped_png_aux_xml
    warped_png + '.aux.xml'
  end

  def public_warped_tif_url
    'mapimages/dst/' + id.to_s + '.tif'
  end

  def public_warped_png_url
    public_warped_tif_url + '.png'
  end

  def mask_file_format
    'gml'
  end

  def temp_filename
    # self.full_filename  + "_temp"
    File.join(warped_dir, id.to_s) + '_temp'
  end

  def masking_file_gml
    Rails.public_path.join('mapimages/', id.to_s).to_s + '.gml'
  end

  # file made when rasterizing
  def masking_file_gfs
    Rails.public_path.join('mapimages/', id.to_s).to_s + '.gfs'
  end

  def masked_src_filename
    unwarped_filename + '_masked'
  end

  #############################################
  # INSTANCE METHODS
  #############################################

  def depicts_year
    issue_year || layers.with_year.collect(&:depicts_year).compact.first
  end

  def warped?
    status == :warped
  end

  def available?
    %i[available warping warped published].include?(status)
  end

  def published?
    status == :published
  end

  def warped_or_published?
    %i[warped published].include?(status)
  end

  def warped_published_and_public?
    %i[warped published].include?(status) && public?
  end

  def update_map_type(map_type)
    return unless Map::MAP_TYPE.include? map_type.to_sym

    update(map_type: map_type.to_sym)
    update_layers
  end

  def last_changed
    if gcps.size > 0
      gcps.last.created_at
    elsif !updated_at.nil?
      updated_at
    elsif !created_at.nil?
      created_at
    else
      Time.now
    end
  end

  def save_rough_centroid(lon, lat)
    self.rough_centroid = Point.from_lon_lat(lon, lat)
    save
  end

  def save_bbox
    _, stdout, stderr = Open3.popen3("#{GDAL_PATH}gdalinfo", warped_filename)
    if stderr.readlines.to_s.size > 0
      logger.debug 'Save bbox error ' + stderr.readlines.to_s
    else
      info = stdout.readlines.to_s
      _, west, south = info.match(/Lower Left\s+\(\s*([-.\d]+),\s+([-.\d]+)/).to_a
      _, east, north = info.match(/Upper Right\s+\(\s*([-.\d]+),\s+([-.\d]+)/).to_a
      self.bbox = [west, south, east, north].join(',')
    end
  end

  def bounds
    if bbox.nil?
      x_array = []
      y_array = []
      gcps.hard.each do |gcp|
        next unless gcp[:lat].is_a? Numeric and gcp[:lon].is_a? Numeric

        x_array << gcp[:lat]
        y_array << gcp[:lon]
      end
      # south, west, north, east
      [y_array.min, x_array.min, y_array.max, x_array.max].join ','
    else
      bbox
    end
  end

  # returns a GeoRuby polygon object representing the bounds
  def bounds_polygon
    bounds_float = bounds.split(',').collect { |i| i.to_f }
    Polygon.from_coordinates([[bounds_float[0..1]], [bounds_float[2..3]]], -1)
  end

  def converted_bbox
    bnds = bounds.split(',')
    cbounds = []
    _, c_out, =
      Open3.popen3("echo #{bnds[0]} #{bnds[1]} | cs2cs +proj=latlong +datum=WGS84 +to +proj=merc +ellps=sphere +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0")
    info = c_out.readlines.to_s
    _, cbounds[0], cbounds[1] = info.match(/([-.\d]+)\s*([-.\d]+).*/).to_a
    _, c_out, =
      Open3.popen3("echo #{bnds[2]} #{bnds[3]} | cs2cs +proj=latlong +datum=WGS84 +to +proj=merc +ellps=sphere +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0")
    info = c_out.readlines.to_s
    _, cbounds[2], cbounds[3] = info.match(/([-.\d]+)\s*([-.\d]+).*/).to_a
    cbounds.join(',')
  end

  def bbox_centroid
    bbox_geom.nil? ? nil : "#{bbox_geom.centroid.x},#{bbox_geom.centroid.x}"
  end

  # attempts to align based on the extent and offset of the
  # reference map's warped image
  # results it nicer gcps to edit with later
  def align_with_warped(srcmap, align = nil, append = false)
    srcmap = Map.find(srcmap)
    origgcps = srcmap.gcps.hard

    # clear out original gcps, unless we want to append the copied gcps to the existing ones
    gcps.hard.destroy_all unless append == true

    # extent of source from gdalinfo
    _, stdout, = Open3.popen3("#{GDAL_PATH}gdalinfo", srcmap.warped_filename)
    info = stdout.readlines.to_s
    _, west, south = info.match(/Lower Left\s+\(\s*([-.\d]+),\s+([-.\d]+)/).to_a
    _, east, north = info.match(/Upper Right\s+\(\s*([-.\d]+),\s+([-.\d]+)/).to_a

    lon_shift = west.to_f - east.to_f
    lat_shift = south.to_f - north.to_f

    origgcps.each do |gcp|
      Gcp.new
      a = gcp.clone
      if align == 'east'
        a.lon -= lon_shift
      elsif align == 'west'
        a.lon += lon_shift
      elsif align == 'north'
        a.lat -= lat_shift
      elsif align == 'south'
        a.lat += lat_shift
      else
        # if no align, then dont change the gcps
      end
      a.map = self
      a.save
    end

    gcps.hard
  end

  # attempts to align based on the width and height of
  # reference map's un warped image
  # results it potential better fit than align_with_warped
  # but with less accessible gpcs to edit
  def align_with_original(srcmap, align = nil, append = false)
    srcmap = Map.find(srcmap)
    origgcps = srcmap.gcps

    # clear out original gcps, unless we want to append the copied gcps to the existing ones
    gcps.hard.destroy_all unless append == true

    origgcps.each do |gcp|
      Gcp.new
      new_gcp = gcp.clone
      if align == 'east'
        new_gcp.x -= srcmap.width

      elsif align == 'west'
        new_gcp.x += srcmap.width
      elsif align == 'north'
        new_gcp.y += srcmap.height
      elsif align == 'south'
        new_gcp.y -= srcmap.height
      else
        # if no align, then dont change the gcps
      end
      new_gcp.map = self
      new_gcp.save
    end

    gcps.hard
  end

  # map gets error attibute set and gcps get error attribute set
  def gcps_with_error(soft = nil)
    gcps = if soft == 'true'
             Gcp.soft.where(['map_id = ?', id]).order(:created_at)
           else
             Gcp.hard.where(['map_id = ?', id]).order(:created_at)
           end
    gcps, map_error = ErrorCalculator.calc_error(gcps)
    @error = map_error
    # send back the gpcs with error calculation
    gcps
  end

  def mask!
    require 'fileutils'

    self.mask_status = :masking
    save!
    format = mask_file_format

    return 'no masking file matching specified format found.' unless format == 'gml'
    return 'no masking file found, have you created a clipping mask and saved it?' unless File.exist?(masking_file_gml)

    masking_file = masking_file_gml
    layer = 'features'

    self.mask_geojson = convert_mask_to_geojson

    masked_src_filename = self.masked_src_filename
    if File.exist?(masked_src_filename)
      # deleting old masked image
      File.delete(masked_src_filename)
    end
    # copy over orig to a new unmasked file
    FileUtils.copy(unwarped_filename, masked_src_filename)

    command = ["#{GDAL_PATH}gdal_rasterize", '-i', '-b', '1', '-b', '2', '-b', '3', '-burn', '17', '-burn', '17',
               '-burn', '17', masking_file, '-l', layer, masked_src_filename]
    r_stdout, r_stderr = Open3.capture3(*command)
    logger.info command

    r_out = r_stdout
    r_err = r_stderr

    # if there is an error, and it's not a warning about SRS
    if r_err.blank?
      r_out = 'Success! Map was cropped!'
    else # && r_err.split[0] != "Warning"
      # error, need to fail nicely
      logger.error 'ERROR gdal rasterize script: ' + r_err
      logger.error 'Output = ' + r_out
      r_out = 'ERROR with gdal rasterise script: ' + r_err + '<br /> You may want to try it again? <br />' + r_out
    end

    self.mask_status = :masked
    save!
    r_out
  end

  # FIXME: -clear up this method - don't return the text, just raise execption if necessary
  #
  # gdal_rasterize -i -burn 17 -b 1 -b 2 -b 3 SSS.json -l OGRGeoJson orig.tif
  # gdal_rasterize -burn 17 -b 1 -b 2 -b 3 SSS.gml -l features orig.tif

  # Main warp method
  def warp!(resample_option, transform_option, use_mask = 'false')
    prior_status = self.status
    # self.status = :warping
    save!

    gcp_array = gcps.hard

    gdal_gcp_array = []
    gcp_array.each do |gcp|
      gdal_gcp_array << gcp.gdal_array
    end
    gdal_gcp_array.flatten!

    mask_options_array = []
    if use_mask == 'true' && self.mask_status == :masked
      src_filename = masked_src_filename
      mask_options_array = ['-srcnodata', '17 17 17']

      self.mask_geojson = convert_mask_to_geojson if mask_geojson.blank?
    else
      src_filename = unwarped_filename
    end

    dest_filename = warped_filename
    temp_filename = self.temp_filename

    # delete existing temp images @map.delete_images
    if File.exist?(dest_filename)
      # logger.info "deleted warped file ahead of making new one"
      File.delete(dest_filename)
    end

    logger.info 'gdal translate'

    command = ["#{GDAL_PATH}gdal_translate", '-a_srs', 'EPSG:4326', '-of', 'VRT', src_filename, "#{temp_filename}.vrt",
               gdal_gcp_array].flatten
    logger.info command
    t_stdout, t_stderr = Open3.capture3(*command)

    t_out = t_stdout
    t_err = t_stderr

    if t_err.blank?
      t_out = "Okay, translate command ran fine! <div id = 'scriptout'>" + t_out + '</div>'
    else
      logger.error 'ERROR gdal translate script: ' + t_err
      logger.error 'Output = ' + t_out
      t_out = 'ERROR with gdal translate script: ' + t_err + '<br /> You may want to try it again? <br />' + t_out
    end
    trans_output = t_out

    memory_limit = APP_CONFIG['gdal_memory_limit'].blank? ? [] : ['-wm', APP_CONFIG['gdal_memory_limit']]

    command = ["#{GDAL_PATH}gdalwarp", memory_limit, transform_option.strip.split, resample_option.strip, '-dstalpha',
               mask_options_array, '-dstnodata', 'none', '-s_srs', 'EPSG:4326', "#{temp_filename}.vrt", dest_filename, '-co', 'TILED=YES', '-co', 'COMPRESS=JPEG'].reject(&:empty?).flatten
    logger.info command

    w_stdout, w_stderr = Open3.capture3(*command)

    w_out = w_stdout
    if non_fatal_gdal_warning?(w_stderr)
      logger.warn "GDAL warp warning: #{w_stderr.strip}"
      w_err = ''
    else
      w_err = w_stderr
    end

    if w_err.blank?
      w_out = "Okay, warp command ran fine! <div id='scriptout'>" + w_out + '</div>'
    else
      logger.error 'Error gdal warp script' + w_err
      logger.error 'output = ' + w_out
      w_out = 'error with gdal warp: ' + w_err + '<br /> try it again?<br />' + w_out
    end
    warp_output = w_out

    # gdaladdo
    command = ["#{GDAL_PATH}gdaladdo", '-r', 'average', dest_filename, '2', '4', '8', '16', '32', '64']
    o_stdout, o_stderr = Open3.capture3(*command)
    logger.info command

    o_out = o_stdout
    if non_fatal_gdal_warning?(o_stderr)
      logger.warn "GDAL overview warning: #{o_stderr.strip}"
      o_err = ''
    else
      o_err = o_stderr
    end
    if o_err.blank?
      o_out = "Okay, overview command ran fine! <div id='scriptout'>" + o_out + '</div>'
    else
      logger.error 'Error gdal overview script' + o_err
      logger.error 'output = ' + o_out
      o_out = 'error with gdal overview: ' + o_err + '<br /> try it again?<br />' + o_out
    end
    overview_output = o_out

    if File.exist?(temp_filename + '.vrt')
      logger.info 'deleted temp vrt file'
      File.delete(temp_filename + '.vrt')
    end

    # don't care too much if overviews threw a random warning
    if w_err.size <= 0 and t_err.size <= 0
      self.status = if prior_status == :published
                      :published
                    else
                      :warped
                    end
      # Spawnling.new do
      #  convert_to_png
      # end
      touch(:rectified_at)
    else
      self.status = :available
    end
    save!
    update_layers
    update_bbox
    'Step 1: Translate: ' + trans_output + '<br />Step 2: Warp: ' + warp_output +
      'Step 3: Add overviews:' + overview_output
  end

  def update_bbox
    return unless File.exist? warped_filename

    logger.info 'updating bbox...'
    begin
      extents = get_raster_extents warped_filename
      self.bbox = extents.join ','
      logger.debug 'SAVING BBOX GEOM'
      poly_array = [
        [extents[0], extents[1]],
        [extents[2], extents[1]],
        [extents[2], extents[3]],
        [extents[0], extents[3]],
        [extents[0], extents[1]]
      ]

      self.bbox_geom = GeoRuby::SimpleFeatures::Polygon.from_coordinates([poly_array]).as_wkt

      save
    rescue Exception => e
      logger.debug e.inspect
    end
  end

  def delete_mask
    logger.info 'delete mask'
    File.delete(masking_file_gml) if File.exist?(masking_file_gml)
    File.delete(masking_file_gml + '.ol') if File.exist?(masking_file_gml + '.ol')
    File.delete(masking_file_gfs) if File.exist?(masking_file_gfs)

    self.mask_status = :unmasked
    save!
    I18n.t('maps.model.delete_mask_success')
  end

  def save_mask(vector_features)
    if mask_file_format == 'gml'
      save_mask_gml(vector_features)
    else
      I18n.t('maps.model.unknown_mask_format')
    end
  end

  # parses geometry from openlayers, and saves it to file.
  # GML format
  def save_mask_gml(features)
    require 'rexml/document'
    File.delete(masking_file_gml) if File.exist?(masking_file_gml)
    File.delete(masking_file_gml + '.ol') if File.exist?(masking_file_gml + '.ol')
    File.delete(masking_file_gfs) if File.exist?(masking_file_gfs)
    origfile = File.new(masking_file_gml + '.ol', 'w+')
    origfile.puts(features)
    origfile.close

    doc = REXML::Document.new features
    # element
    REXML::XPath.each(doc, '//gml:coordinates') do |element|
      # blimey element.text.split(' ').map {|i| i.split(',')}.map{ |i| i[0] => i[1]}.inject({}){|i,j| i.merge(j)}
      coords_array = element.text.split(' ')
      new_coords_array = []
      coords_array.each do |coordpair|
        coord = coordpair.split(',')
        coord[1] = height - coord[1].to_f
        newcoord = coord.join(',')
        new_coords_array << newcoord
      end
      element.text = new_coords_array.join(' ')
    end
    gmlfile = File.new(masking_file_gml, 'w+')
    doc.write(gmlfile)
    gmlfile.close
    I18n.t('maps.model.gml_mask_saved')
  end

  def self.to_csv
    CSV.generate(col_sep: ';') do |csv|
      csv << %w[id title description authors bbox bbox_centroid call_number created_at updated_at
                date_depicted filename import_id issue_year map_type mask_status owner_id public
                metadata_lat metadata_lon metadata_projection
                publication_place published_date publisher rectified_at reprint_date scale source_uri status
                subject_area unique_id upload_content_type upload_file_name upload_file_size height width] ## Header values of CSV
      all.each do |m|
        csv << [m.id, m.title, m.description, m.authors, m.bbox, m.bbox_centroid, m.call_number, m.created_at, m.updated_at,
                m.date_depicted, m.filename, m.import_id, m.issue_year, m.map_type, m.mask_status, m.owner_id, m.public,
                m.metadata_lat, m.metadata_lon, m.metadata_projection,
                m.publication_place, m.published_date, m.publisher, m.rectified_at, m.reprint_date, m.scale, m.source_uri, m.status,
                m.subject_area, m.unique_id, m.upload_content_type, m.upload_file_name, m.upload_file_size, m.height, m.width] # #Row values of CSV
      end
    end
  end

  def has_metadata_location?
    metadata_lat.present? && metadata_lon.present?
  end

  ############
  # PRIVATE
  ############

  def convert_to_png
    logger.info "start convert to png ->  #{warped_png_filename}"
    ext_command = ["#{GDAL_PATH}gdal_translate", '-of', 'png', warped_filename, warped_png_filename]
    stdout, stderr = Open3.capture3(*ext_command)
    logger.debug ext_command
    if stderr.blank?
      logger.info "end, converted to png -> #{warped_png_filename}"
    else
      logger.error "ERROR convert png #{warped_filename} -> #{warped_png_filename}"
      logger.error stderr
      logger.error stdout
    end
  end

  # uses geocode.xyz geoparse api
  def find_bestguess_places
    return { status: 'fail', code: 'geoparse disabled' } if APP_CONFIG['geoparse_enable'] == false

    uri = URI('https://geocode.xyz')
    scantext = ERB::Util.h(title.to_s) + ' ' + ERB::Util.h(description.to_s)

    begin
      form_data = { 'scantext' => scantext, 'geojson' => '1' }
      if APP_CONFIG['geoparse_region'].present?
        form_data = form_data.merge({ 'region' => APP_CONFIG['geoparse_region'] })
      end
      if APP_CONFIG['geoparse_geocodexyz_key'].present?
        form_data = form_data.merge({ 'auth' => APP_CONFIG['geoparse_geocodexyz_key'] })
      end

      req = Net::HTTP::Post.new(uri)
      req.set_form_data(form_data)

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 2) do |http|
        http.request(req)
      end

      results = JSON.parse(res.body)

      if results['properties']['matches'].to_i > 0
        places = []
        found_places = results['features']
        max_lat = -90.0
        max_lon = -180.0
        min_lat = -90.0
        min_lon = 180.0
        found_places.each do |found_place|
          place_hash = {}
          place_hash[:name] = found_place['properties']['location']
          lon = place_hash[:lon] = found_place['geometry']['coordinates'][0]
          lat = place_hash[:lat] = found_place['geometry']['coordinates'][1]
          places << place_hash

          max_lat = lat.to_f if lat.to_f > max_lat
          min_lat = lat.to_f if lat.to_f < min_lat
          max_lon = lon.to_f if lon.to_f > max_lon
          min_lon = lon.to_f if lon.to_f < min_lon
        end

        extents = [min_lon, min_lat, max_lon, max_lat].join(',')
        sibling_extent = if !layers.visible.empty? && !layers.visible.first.maps.warped.empty?
                           layers.visible.first.maps.warped.last.bbox
                         end

        placemaker_result = { status: 'ok', map_id: id, extents: extents, count: places.size,
                              places: places, sibling_extent: sibling_extent }

      else
        placemaker_result = { status: 'fail', code: 'no results' }
      end
    rescue JSON::ParserError => e
      logger.error 'JSON ParserError in find bestguess places ' + e.to_s
      placemaker_result = { status: 'fail', code: 'jsonError' }
    rescue Net::ReadTimeout => e
      logger.error 'timeout in find bestguess places, probably throttled ' + e.to_s
      placemaker_result = { status: 'fail', code: 'timeout' }
    rescue Net::HTTPBadResponse => e
      logger.error 'http bad response in find bestguess places ' + e.to_s
      placemaker_result = { status: 'fail', code: 'badResponse' }
    rescue SocketError => e
      logger.error 'Socket error in find bestguess places ' + e.to_s
      placemaker_result = { status: 'fail', code: 'socketError' }
    rescue StandardError => e
      logger.error 'StandardError ' + e.to_s
      placemaker_result = { status: 'fail', code: 'StandardError' }
    end

    placemaker_result
  end

  def clear_cache
    Rails.cache.delete_matched ".*/maps/wms/#{id}.png?status=warped.*"
    Rails.cache.delete_matched "*/maps/tile/#{id}/*"
  end

  # takes in the clipping mask file, transforms it to geo and converts to geojson, returning the geojson
  def convert_mask_to_geojson
    if gcps.hard.size < 3
      nil
    else
      gcp_array = gcps.hard

      gdal_gcp_array = []
      gcp_array.each do |gcp|
        gdal_gcp_array << gcp.gdal_array
      end
      gdal_gcp_array.flatten!

      command = ['ogr2ogr', '-f', 'geojson', '-s_srs', 'epsg:4326', '-t_srs', 'epsg:3857', gdal_gcp_array,
                 '/dev/stdout', masking_file_gml].flatten
      logger.info command
      o_out, o_err = Open3.capture3(*command)

      if o_err.present?
        logger.error 'Error ogr2ogr script' + o_err
        logger.error 'output = ' + o_out
        return nil
      end

      o_out
    end
  end

  def non_fatal_gdal_warning?(output)
    return false if output.blank?

    messages = output.to_s.lines.map(&:strip).reject(&:blank?)
    return false if messages.empty?

    messages.all? do |line|
      NON_FATAL_GDAL_WARNING_PATTERNS.any? { |pattern| pattern.match?(line) }
    end
  end
end
