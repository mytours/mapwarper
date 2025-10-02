source 'https://rubygems.org'

ruby '>= 3.2'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 8.0'
# Use sqlite3 as the database for Active Record
# gem 'sqlite3'

# Asset pipeline and frontend
gem 'importmap-rails' # For JavaScript with ESM
gem 'propshaft' # Replaces sprockets in Rails 8
gem 'sass-rails'
gem 'stimulus-rails'
gem 'turbo-rails'
# Use Uglifier as compressor for JavaScript assets
# gem 'uglifier', '>= 1.3.0'
# Use CoffeeScript for .js.coffee assets and views
# gem 'coffee-rails', '~> 4.0.0'
# See https://github.com/sstephenson/execjs#readme for more supported runtimes
# gem 'therubyracer',  platforms: :ruby

# Use jquery as the JavaScript library
gem 'jquery-rails'
# Turbolinks makes following links in your web application faster. Read more: https://github.com/rails/turbolinks
# gem 'turbolinks'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder'
# bundle exec rake doc:rails generates the API under doc/api.
# gem 'sdoc', '~> 0.4.0',          group: :doc

# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use unicorn as the app server
# gem 'unicorn'

# Use debugger
# gem 'debugger', group: [:development, :test]

gem 'devise', '>= 4.9'

gem 'devise-encryptable'

gem 'oauth', '>= 0.5.8'
gem 'oauth2'
gem 'omniauth-oauth2'

gem 'omniauth-facebook'
gem 'omniauth-github'
gem 'omniauth-mediawiki'
gem 'omniauth-osm'
gem 'omniauth-rails_csrf_protection', '~> 1.0'
gem 'omniauth-twitter'

gem 'hcaptcha'

gem 'pg', '~> 1.5'

gem 'activerecord-postgis-adapter'

gem 'acts-as-taggable-on', '~> 12.0'
# Paperclip is deprecated, but keeping for now - should migrate to ActiveStorage
gem 'acts_as_commentable'
gem 'kt-paperclip' # Rails 7+ compatible fork
gem 'spawnling', '~>2.1'
gem 'will_paginate'

# Rails 4 support for the audited (acts_as_audited gem) is not quite rails4 worthy - see #https://github.com/collectiveidea/audited/pull/166
# gem 'audited-activerecord', github: 'timwaters/audited', branch: 'rails4'
gem 'audited'

gem 'georuby'

# Caching - Redis for Rails 8
gem 'hiredis-client'
gem 'redis', '>= 4.0'

gem 'rails-i18n'

gem 'pg_search'

# Rails API functionality is now built into Rails
# gem 'rails-api'
gem 'active_model_serializers'
# Token authentication is handled by Devise in Rails 8
# gem 'simple_token_authentication', '~> 1.0'
gem 'rack-cors', require: 'rack/cors'

gem 'marcel' # Replaces mimemagic
gem 'nokogiri', '>= 1.10.10'
gem 'redcarpet', '>= 3.5.1'

gem 'csv'

gem "puma"
gem "matrix"

group :development do
  gem 'web-console'
  # gem 'spring'  # Spring is deprecated in Rails 8
  gem 'capistrano', '~> 3.18'
  gem 'capistrano-bundler', require: false
  gem 'capistrano-rails', require: false
  gem 'i18n-tasks'
  gem 'rubocop', require: false
  gem 'rubocop-factory_bot', require: false
  gem 'rubocop-rails-omakase', require: false
  gem 'rvm1-capistrano3', require: false
  gem 'thin'
end

group :test do
  gem 'factory_bot_rails' # Renamed from factory_girl_rails
  gem 'mocha'
  gem 'webmock'
end
