class Membership < ActiveRecord::Base
  belongs_to :group
  belongs_to :user
  validates :user_id, uniqueness: { scope: :group_id, message: 'User is already a member of this group' }
end
