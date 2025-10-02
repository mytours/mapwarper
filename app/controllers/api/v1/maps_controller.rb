class Api::V1::MapsController < Api::V1::ApiController
  before_action :authenticate_user!,       except: %i[show index status gcps]
  before_action :check_administrator_role, only: %i[publish unpublish]
  before_action :find_map,
                only: %i[show update destroy gcps rectify mask delete_mask crop mask_crop_rectify publish unpublish
                         status]
  before_action :can_edit_map, only: %i[update destroy]

  before_action :validate_jsonapi_type, only: %i[create update]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActionController::ParameterMissing, with: :missing_param_error

  # params: page, per_page, query, field, sort_key, sort_order, field, show_warped, bbox, operation
  def index
    # if being called from layer#maps
    layer_conditions = nil
    if index_params[:layer_id]
      layer = Layer.find(index_params[:layer_id])
      layer_conditions = { id: layer.maps.map(&:id) }
    end

    # sort / order
    sort_order = 'desc'
    sort_order = 'asc' if index_params[:sort_order] == 'asc'
    sort_key = %w[title status created_at updated_at].detect { |f| f == index_params[:sort_key] }
    sort_key ||= 'updated_at'
    sort_nulls = if sort_order == 'desc'
                   ' NULLS LAST'
                 else
                   ' NULLS FIRST'
                 end

    order_options = "#{sort_key} #{sort_order} #{sort_nulls}"

    # pagination
    paginate_options = {
      page: index_params[:page],
      per_page: index_params[:per_page] || 50
    }

    # query
    query = index_params[:query]

    field = %w[tags title description status publisher authors].detect { |f| f == index_params[:field] }
    field ||= 'title'
    if query && query.strip.length > 0 && field
      query = query.gsub(/\W/, ' ')
      query_options = ["#{field}  ~* ?", '(:punct:|^|)' + query + '([^A-z]|$)']
    else
      query_options = nil
    end

    # show_warped
    warped_options = nil
    if index_params[:show_warped] == '1'
      warped_options = { status: [Map.status(:warped), Map.status(:published)], map_type: Map.map_type(:is_map) }
    end

    # bbox
    bbox_conditions = nil
    sort_geo = nil

    # extents = [-74.1710,40.5883,-73.4809,40.8485] #NYC
    if params[:bbox] && params[:bbox].split(',').size == 4
      extents = nil
      begin
        extents = params[:bbox].split(',').collect { |i| Float(i) }
      rescue ArgumentError
        logger.debug 'arg error with bbox, setting extent to defaults'
        # TODO: send back error message here instead of defaults
      end
      if extents
        bbox_poly_ary = [
          [extents[0], extents[1]],
          [extents[2], extents[1]],
          [extents[2], extents[3]],
          [extents[0], extents[3]],
          [extents[0], extents[1]]
        ]
        bbox_polygon = GeoRuby::SimpleFeatures::Polygon.from_coordinates([bbox_poly_ary], -1).as_ewkt
        bbox_conditions = if params[:operation] == 'within'
                            ["ST_Within(bbox_geom, ST_GeomFromText('#{bbox_polygon}'))"]
                          else
                            ["ST_Intersects(bbox_geom, ST_GeomFromText('#{bbox_polygon}'))"]
                          end

        sort_geo = if params[:operation] == 'intersect'
                     "ABS(ST_Area(bbox_geom) - ST_Area(ST_GeomFromText('#{bbox_polygon}'))) ASC"
                   else
                     'ST_Area(bbox_geom) DESC'
                   end
      end

    end

    @maps = Map.all.where(layer_conditions).where(warped_options).where(query_options).where(bbox_conditions).order(order_options).order(sort_geo).paginate(paginate_options)

    if request.format == 'geojson'
      render json: @maps, each_serializer: MapGeoSerializer, adapter: :attributes
      return
    end
    # ActiveSupport.escape_html_entities_in_json = false
    render json: @maps,
           include: %w[layers owner],
           meta: { 'total_entries' => @maps.total_entries,
                   'total_pages' => @maps.total_pages }
  end

  def show
    if request.format == 'geojson'
      render json: @map, serializer: MapGeoSerializer, adapter: :attributes
      return
    end
    render json: @map, include: %w[layers owner]
  end

  def create
    @map = Map.new(map_params)

    if user_signed_in?
      @map.owner = current_user
      @map.users << current_user
    end

    if @map.save
      render json: @map, status: :created
    else
      render json: @map, status: :unprocessable_entity, serializer: ActiveModel::Serializer::ErrorSerializer
    end
  end

  def update
    map_params.extract!(:upload, :upload_url)

    if @map.update_attributes(map_params)
      render json: @map
    else
      render json: @map, status: :unprocessable_entity, serializer: ActiveModel::Serializer::ErrorSerializer
    end
  end

  def destroy
    return unless @map.destroy

    render json: @map
  end

  def gcps
    render json: @map.gcps_with_error, meta: { 'map_error' => @map.error }
  end

  # patch warp
  def rectify
    resample_param = params[:resample_options]
    transform_param = params[:transform_options]
    params[:mask]
    transform_option = case transform_param
                       when 'auto'
                         ''
                       when 'p1'
                         ' -order 1 '
                       when 'p2'
                         ' -order 2 '
                       when 'p3'
                         ' -order 3 '
                       when 'tps'
                         ' -tps '
                       else
                         ''
                       end

    resample_option = case resample_param
                      when 'near'
                        ' -rn '
                      when 'bilinear'
                        ' -rb '
                      when 'cubic'
                        ' -rc '
                      when 'cubicspline'
                        ' -rcs '
                      when 'lanczos' # its very very slow
                        ' -rn '
                      else
                        ' -rn'
                      end

    use_mask = params[:use_mask]
    if @map.gcps.hard.size.nil? || @map.gcps.hard.size < 3
      render json: { errors: [{ title: 'Not enough gcps', detail: 'Map needs at least 3 control points to rectify' }] },
             status: :unprocessable_entity
      return false
    end
    if @map.status == :warping
      render json: { errors: [{ title: 'Map busy', detail: 'Map currently being rectified. Try again later.' }] },
             status: :unprocessable_entity
      return false
    end

    @map.warp! transform_option, resample_option, use_mask

    @map.clear_cache

    render json: @map
  end

  # post saves the mask
  def mask
    if @map.save_mask(params[:output])
      render json: @map
    else
      render json: { errors: [{ title: 'Mask error', detail: 'Error with saving mask' }] },
             status: :unprocessable_entity
    end
  end

  def delete_mask
    if @map.delete_mask
      render json: @map
    else
      render json: { errors: [{ title: 'Mask error', detail: 'Error with deleting mask' }] },
             status: :unprocessable_entity
    end
  end

  def crop
    unless File.exist?(@map.masking_file_gml)
      render json: { errors: [{ title: 'Mask error', detail: 'Mask file not found' }] },
             status: :unprocessable_entity
      return false
    end
    if @map.mask!
      render json: @map
    else
      render json: { errors: [{ title: 'Mask error', detail: 'Error with cropping map' }] },
             status: :unprocessable_entity
    end
  end

  # 1. save mask
  # 2. mask map
  # 3. forward on to rectify
  def mask_crop_rectify
    if @map.save_mask(params[:output]) && @map.mask!
      params[:use_mask] = 'true'
      rectify
    else
      render json: { errors: [{ title: 'Saving and masking error', detail: 'Error with saving and masking map' }] },
             status: :unprocessable_entity
    end
  end

  def publish
    unless @map.status == :warped
      render json: { errors: [{ title: 'Map not warped', detail: 'Map is not warped so cannot be published' }] },
             status: :unprocessable_entity
      return false
    end
    if @map.publish
      render json: @map
    else
      render json: { errors: [{ title: 'Publish error', detail: 'Error with publishing map' }] },
             status: :unprocessable_entity
    end
  end

  def unpublish
    unless @map.status == :published
      render json: { errors: [{ title: 'Publish error', detail: 'Map is not published so cannot be unpublished' }] },
             status: :unprocessable_entity
      return false
    end
    if @map.unpublish
      render json: @map
    else
      render json: { errors: [{ title: 'Publish error', detail: 'Error with unpublishing map' }] },
             status: :unprocessable_entity
    end
  end

  def status
    render text: @map.status
  end

  private

  def map_params
    params.require(:data).require(:attributes).permit(:title, :description, :tag_list, :map_type, :subject_area, :unique_id,
                                                      :source_uri, :call_number, :publisher, :publication_place, :authors, :date_depicted, :scale,
                                                      :metadata_projection, :metadata_lat, :metadata_lon,
                                                      :upload_url, :upload, :issue_year, :upload_file_name)
  end

  def index_params
    params.permit(:page, :per_page, :query, :field, :sort_key, :sort_order, :show_warped, :bbox, :operation, :format,
                  :layer_id, :id)
  end

  def find_map
    @map = Map.find(params[:id])
  end

  def can_edit_map
    return if user_signed_in? and ((current_user == @map.owner) or current_user.has_role?('editor'))

    permission_denied
  end
end
