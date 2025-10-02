class ImportsController < ApplicationController
  before_action :authenticate_user!
  before_action :check_administrator_role

  before_action :find_import, except: %i[index new create exports]
  before_action :check_imported, only: [:start]

  rescue_from ActiveRecord::RecordNotFound, with: :bad_record

  helper :sort
  include SortHelper

  def index
    @imports = Import.order('updated_at DESC').paginate(page: params[:page], per_page: 30)
  end

  def show; end

  def new
    @import = Import.new
  end

  def edit; end

  def create
    @import = Import.new(import_params)
    @import.user = current_user
    if @import.save
      flash[:notice] = t('.flash')
      redirect_to import_url(@import)
    else
      flash[:error] = t('.error')
      render action: 'new'
    end
  end

  def update
    if @import.update_attributes(import_params)
      @import.file_count = @import.dir_file_count
      flash[:notice] = t('.flash')
      redirect_to import_url(@import)
    else
      flash[:error] = t('.error')
      render action: 'edit'
    end
  end

  def destroy
    flash[:notice] = if @import.destroy
                       t('.flash')
                     else
                       t('.error')
                     end
    redirect_to imports_path
  end

  def start
    return unless @import.status == :ready

    @import.prepare_run
    Spawnling.new do
      @import.import!({ async: true })
    end
  end

  def status
    render json: { status: @import.status, count: @import.imported_count }
  end

  def maps
    sort_init('created_at', { default_order: 'desc' })
    sort_update
    sort_nulls = if params[:sort_order] && params[:sort_order] == 'desc'
                   ' NULLS LAST'
                 else
                   ' NULLS FIRST'
                 end
    order_options = sort_clause + sort_nulls

    @maps = @import.maps.order(order_options).paginate(page: params[:page], per_page: 50)
  end

  def log
    send_file @import.log_path, disposition: :inline, type: 'text/plain'
  end

  def exports; end

  private

  def find_import
    @import = Import.find(params[:id])
  end

  def check_imported
    return unless @import.status == :finished

    flash[:notice] = t('imports.start.already_imported_error')
    redirect_to imports_path
  end

  def bad_record
    respond_to do |format|
      format.html do
        flash[:notice] = t('imports.show.not_found')
        redirect_to :root
      end
      format.json { render json: { stat: 'not found', items: [] }.to_json, status: :not_found }
    end
  end

  def import_params
    params.require(:import).permit(:name, :metadata, layer_ids: [])
  end
end
