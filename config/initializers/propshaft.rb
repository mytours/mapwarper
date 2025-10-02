# Propshaft configuration for Rails 8
# Propshaft replaces Sprockets as the asset pipeline

Rails.application.config.assets.paths << Rails.root.join('app/assets/images')
Rails.application.config.assets.paths << Rails.root.join('vendor/assets/javascripts')
Rails.application.config.assets.paths << Rails.root.join('vendor/assets/stylesheets')
