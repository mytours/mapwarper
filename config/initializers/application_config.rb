CONFIG_PATH = "#{Rails.root.join('config/application.yml')}"

APP_CONFIG = YAML.load_file(CONFIG_PATH, aliases: true)[Rails.env]

# directories for maps and layer/mosaic tileindex shapefiles
DST_MAPS_DIR = APP_CONFIG['dst_maps_dir'].presence || Rails.public_path.join('mapimages/dst/').to_s
SRC_MAPS_DIR = APP_CONFIG['src_maps_dir'].presence || Rails.public_path.join('mapimages/src/').to_s
TILEINDEX_DIR = APP_CONFIG['tileindex_dir'].presence || Rails.root.join('db/maptileindex').to_s

ENV['HCAPTCHA_SITE_KEY'] = APP_CONFIG['hcaptcha_key'].presence
ENV['HCAPTCHA_SECRET_KEY'] = APP_CONFIG['hcaptcha_secret'].presence

# if gdal is not on the normal path
GDAL_PATH = APP_CONFIG['gdal_path'] || ''

#
# Uncomment and populate the config file if you want to enable:
# MAX_DIMENSION = will reduce the dimensions of the image when uploaded
# MAX_ATTACHMENT_SIZE = will reject files that are bigger than this
# APP_CONFIG['gdal_memory_limit'] = limit the amount of memory available to gdal
#
# MAX_DIMENSION = APP_CONFIG['max_dimension']
# MAX_ATTACHMENT_SIZE = APP_CONFIG['max_attachment_size']
# GDAL_MEMORY_LIMIT = APP_CONFIG['gdal_memory_limit']

Rails.application.routes.default_url_options[:host] = APP_CONFIG['host']
ActionMailer::Base.default_url_options[:host] = APP_CONFIG['host']
ActionMailer::Base.delivery_method = :sendmail
Devise.mailer_sender = APP_CONFIG['email']
