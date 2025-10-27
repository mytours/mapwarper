require "#{Rails.root.join('app/lib/enum_fu/lib/enum_fu.rb')}"
ActiveRecord::Base.include EnumFu
