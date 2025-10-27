class GroupsController < ApplicationController
  before_action :find_group, only: %i[show edit update destroy]

  before_action :authenticate_user!, except: [:index]
  before_action :check_administrator_role, only: %i[new create edit update destroy]

  rescue_from ActiveRecord::RecordNotFound, with: :bad_record

  helper :sort
  include SortHelper

  def index
    @html_title = 'Browse Groups'
    sort_init 'id'
    sort_update
    @query = params[:query]
    @field = %w[name description].detect { |f| f == params[:field] }
    conditions = if @query && @query.strip.length > 0 && @field
                   ["#{@field}  ~* ?", '(:punct:|^|)' + @query + '([^A-z]|$)']
                 end

    @groups = Group.where(conditions).order('updated_at DESC').paginate(page: params[:page],
                                                                        per_page: 20).includes(:groups_maps)
  end

  def show
    @group_maps = @group.maps.order('groups_maps.created_at DESC').paginate(page: params[:page], per_page: 10)
    @group_users = @group.users.order('memberships.created_at DESC').paginate(page: params[:page], per_page: 100)
    @html_title = 'Showing Group ' + @group.id.to_s
  end

  def new
    @group = Group.new
  end

  def edit; end

  def create
    @group = Group.new(group_params)
    @group.creator = current_user
    if @group.save
      flash[:notice] = 'New Group Created!'
      redirect_to group_url(@group)
    else
      render action: 'new'
    end
  end

  def update
    if @group.update(group_params)
      flash[:notice] = 'Successfully updated group.'
      redirect_to group_url(@group)
    else
      render action: 'edit'
    end
  end

  def destroy
    # if (group.creator == current_user) or admin_authorized?
    flash[:notice] = if @group.destroy
                       'Group deleted!'
                     else
                       "Group couldn't be deleted."
                     end

    redirect_to groups_path
  end

  private

  def find_group
    @group = Group.find(params[:id])
  end

  def bad_record
    # logger.error("not found #{params[:id]}")
    respond_to do |format|
      format.html do
        flash[:notice] = 'Group not found'
        redirect_to :root
      end
      format.json { render json: { stat: 'not found', items: [] }.to_json, status: :not_found }
    end
  end

  def group_params
    params.require(:group).permit(:name, :description)
  end
end
