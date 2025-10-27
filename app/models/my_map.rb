class MyMap < ActiveRecord::Base
  belongs_to :user
  belongs_to :map
  validates :user_id, uniqueness: { scope: :map_id, message: :not_unique }
end
