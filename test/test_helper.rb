ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
# require "mocha/test_unit"
require 'mocha/minitest'

FileUtils.cp(Dir[Rails.root.join('test/fixtures/data/*.tif').to_s].select do |f|
  test 'f', f
end, Rails.root.join('test/fixtures/data/src/').to_s)

Minitest.after_run do
  FileUtils.rm(Dir.glob(Rails.root.join('test/fixtures/data/src/*').to_s))
  FileUtils.rm(Dir.glob(Rails.root.join('test/fixtures/data/tileindex/*').to_s))
end

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  Map.auditing_enabled = false
  Gcp.auditing_enabled = false

  Object.send(:remove_const, :SRC_MAPS_DIR)
  Object.const_set('SRC_MAPS_DIR', Rails.root.join('test/fixtures/data/src/').to_s)
  Object.send(:remove_const, :DST_MAPS_DIR)
  Object.const_set('DST_MAPS_DIR', Rails.root.join('test/fixtures/data/dst/').to_s)

  Object.send(:remove_const, :TILEINDEX_DIR)
  Object.const_set('TILEINDEX_DIR', Rails.root.join('test/fixtures/data/tileindex/').to_s)

  Paperclip::Attachment.default_options[:path] =
    "#{Rails.root.join('test/test_files/:class/:id_partition/:style.:extension')}"

  def admin_sign_in
    @admin_user = FactoryBot.create(:admin)
    sign_in(@admin_user, scope: :user)
  end

  def normal_user_sign_in
    @user = FactoryBot.create(:user)
    sign_in(@user, scope: :user)
  end

  def editor_user_sign_in
    @editor_user = FactoryBot.create(:editor)
    sign_in(@editor_user, scope: :user)
  end
end

# from http://stackoverflow.com/questions/4901306/how-can-i-mute-rails-3-deprecation-warnings-selectively
# we are doing it manually anyhow..
module ActiveSupport
  class Deprecation
    module Reporting
      # Mute specific deprecation messages
      def warn(message = nil, callstack = nil)
        return if message.match(/Automatic updating of counter caches/)

        super
      end
    end
  end
end
