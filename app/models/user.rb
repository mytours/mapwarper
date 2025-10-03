class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  # :encryptable  for custom authentication methods
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable,
         :omniauthable, omniauth_providers: %i[osm_oauth2 facebook github]

  before_create :generate_authentication_token

  has_many :permissions
  has_many :roles, through: :permissions

  has_many :my_maps, dependent: :destroy
  has_many :maps, -> { uniq }, through: :my_maps

  has_many :layers, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :groups, through: :memberships
  has_many :user_warnings

  validates :login, presence: true
  validates :login, length: { within: 3..40 }
  validates :login, uniqueness: { scope: :email, case_sensitive: false }

  after_destroy :delete_maps

  def has_role?(name)
    roles.find_by_name(name) ? true : false
  end

  def own_maps
    Map.where(['owner_id = ?', id])
  end

  def own_this_map?(map_id)
    Map.exists?(id: map_id.to_i, owner_id: id)
  end

  def own_this_layer?(layer_id)
    Layer.exists?(id: layer_id.to_i, user_id: id)
  end

  # override the confirm method from devise, called when a user confirms their email. Email auth only
  def confirm!
    UserMailer.new_registration(self).deliver_now
    super
  end

  def force_confirm!
    update_column(:confirmed_at, Time.now.utc)
  end

  def provider_name
    if provider && provider == 'mediawiki'
      I18n.t('devise.shared.links.wikimedia')
    elsif provider && provider == 'osm'
      I18n.t('devise.shared.links.openstreetmap')
    else
      provider
    end
  end

  # Called by Devise
  # Method checks to see if the user is enabled (it will therefore not allow a user who is disabled to log in)
  def active_for_authentication?
    super && enabled? && is_allowed_in?
  end

  def inactive_message
    is_allowed_in? ? super : :not_allowed_in
  end

  def self.find_for_twitter_oauth(auth, _signed_in_resource = nil)
    user = User.where(provider: auth.provider, uid: auth.uid).first
    # Create user if not exists
    unless user
      user = User.new(
        login: auth.extra.raw_info.name,
        provider: auth.provider,
        uid: auth.uid,
        email: "#{auth.info.nickname}@twitter.com", # make sure this is unique
        password: Devise.friendly_token[0, 20]
      )
      user.skip_confirmation!
      user.save!
    end
    user
  end

  def self.find_for_osm_oauth(auth, _signed_in_resource = nil)
    user = User.where(provider: auth.provider, uid: auth.uid).first
    # Create user if not exists
    unless user
      user = User.new(
        login: auth.info.display_name,
        provider: auth.provider,
        uid: auth.uid,
        email: "#{auth.info.display_name}+warper@osm.org", # make sure this is unique
        password: Devise.friendly_token[0, 20]
      )
      user.skip_confirmation!
      user.save!
    end
    user
  end

  def self.find_for_mediawiki_oauth(auth, _signed_in_resource = nil)
    user = User.where(provider: auth.provider, uid: auth.uid.to_s).first
    # Create user if not exists
    unless user
      user = User.new(
        login: auth.info.name,
        provider: auth.provider,
        uid: auth.uid,
        email: "#{auth.info.name}+warper@mediawiki.org", # make sure this is unique
        password: Devise.friendly_token[0, 20]
      )
      user.skip_confirmation!
      user.save!
    end
    user
  end

  def self.find_for_github_oauth(auth, _signed_in_resource = nil)
    user = User.where(provider: auth.provider, uid: auth.uid.to_s).first

    unless user
      user = User.new(
        login: auth.info.name,
        provider: auth.provider,
        uid: auth.uid,
        email: "#{auth.info.nickname}+warper@github.com", # make sure this is unique
        password: Devise.friendly_token[0, 20]
      )
      user.skip_confirmation!
      user.save!
    end
    user
  end

  def self.find_for_facebook_oauth(auth, _signed_in_resource = nil)
    user = User.where(provider: auth.provider, uid: auth.uid.to_s).first
    logger.debug auth.info.inspect
    unless user
      user = User.new(
        login: auth.info.name,
        provider: auth.provider,
        uid: auth.uid,
        email: 'warper_fb_' + auth.info['email'], # make sure this is unique
        password: Devise.friendly_token[0, 20]
      )
      user.skip_confirmation!
      user.save!
    end

    user
  end

  alias devise_valid_password? valid_password?

  def valid_password?(password)
    super
  rescue BCrypt::Errors::InvalidHash
    return false unless Devise::Encryptable::Encryptors::LegacyRestfulauthentication.digest(password, nil, nil,
                                                                                            nil) == encrypted_password

    logger.info "User #{email} is using the old password hashing method, updating password to bcrypt."
    self.password = password
    true
  end

  def update_own_maps_count
    update_column(:own_maps_count, own_maps.count)
  end

  # upload_file_size is in bytes
  def update_upload_filesize_sum
    update_column(:upload_filesize_sum, own_maps.sum(:upload_file_size))
  end

  def update_map_counts
    update_own_maps_count
    update_upload_filesize_sum
  end

  def update_disk_usage
    update_column(:disk_usage, calculate_disk_usage)
  end

  # returns tiffed disk usage in units of bytes
  def calculate_disk_usage
    user_own_maps = own_maps # saves 4 calls

    files = user_own_maps.map do |m|
      m.unwarped_filename if File.exist? m.unwarped_filename
    end + user_own_maps.map do |m|
            m.masked_src_filename if File.exist? m.masked_src_filename
          end + user_own_maps.map do |m|
                  m.warped_filename if File.exist? m.warped_filename
                end + user_own_maps.map do |m|
                        m.warped_png_filename if File.exist? m.warped_png_filename
                      end
    files.compact!

    files.inject(0) { |result, file| result + File.size(file) }
  end

  def ensure_authentication_token!
    return authentication_token if authentication_token.present?

    token = generate_unique_authentication_token
    update_columns(authentication_token: token)
    self.authentication_token = token
  end

  def reset_authentication_token!
    update!(authentication_token: generate_unique_authentication_token)
    authentication_token
  end

  def valid_authentication_token?(token)
    return false if token.blank? || authentication_token.blank?

    return false unless authentication_token.bytesize == token.bytesize

    ActiveSupport::SecurityUtils.secure_compare(authentication_token, token)
  end

  def self.authenticate_by_token(authentication_token:, identifier: nil)
    return nil if authentication_token.blank?

    user = if identifier.present?
             find_by(id: identifier) || find_by(email: identifier)
           else
             find_by(authentication_token: authentication_token)
           end
    return nil unless user&.valid_authentication_token?(authentication_token)

    user
  end

  def self.ensure_authentication_tokens!
    find_each(&:ensure_authentication_token!)
  end

  protected

  def is_allowed_in?
    APP_CONFIG['disabled_site'] != true || (has_role?('administrator') || has_role?('trusted'))
  end

  # called after the user has been destroyed
  # delete all user maps
  def delete_maps
    own_maps.each do |map|
      logger.debug "deleting map #{map.inspect}"
      map.destroy
    end
  end

  private

  def generate_authentication_token
    self.authentication_token ||= generate_unique_authentication_token
  end

  def generate_unique_authentication_token
    loop do
      token = SecureRandom.urlsafe_base64(22)
      break token unless self.class.exists?(authentication_token: token)
    end
  end
end
