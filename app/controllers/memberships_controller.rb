class MembershipsController < ApplicationController
  before_action :find_group

  before_action :authenticate_user!

  def new
    membership = @group.memberships.new(user: current_user)
    flash[:notice] = if membership.save
                       'Added to group!'
                     else
                       membership.errors.on(:user_id)
                     end
    redirect_to group_path(@group)
  end

  def destroy
    membership = @group.memberships.find_by_user_id(params[:id])
    flash[:notice] = if membership.destroy
                       'You have left the group'
                     else
                       "Couldn't leave group for some reason."
                     end

    redirect_to group_path(@group)
  end

  protected

  def find_group
    @group = Group.find(params[:group_id])
  end
end
