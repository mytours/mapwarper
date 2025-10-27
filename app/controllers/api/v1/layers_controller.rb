class Api::V1::LayersController < Api::V1::ApiController
  before_action :authenticate_user!,       except: %i[show index]
  before_action :check_administrator_role, only: %i[toggle_visibility merge]
  before_action :find_layer,
                only: %i[show update destroy toggle_visibility remove_map merge]
  before_action :can_edit_layer, only: %i[update destroy remove_map]
  before_action :validate_jsonapi_type, only: %i[create update]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActionController::ParameterMissing, with: :missing_param_error

  # index
  def index
    # map_conditions
    # maps/map_id/layers
    map_conditions = nil
    if index_params[:map_id]
      map = Map.find(index_params[:map_id])
      map_conditions = { id: map.layers.map(&:id) }
    end

    # sort / order
    sort_order = 'desc'
    sort_order = 'asc' if index_params[:sort_order] == 'asc'
    sort_key = %w[name created_at updated_at percent].detect { |f| f == index_params[:sort_key] }
    sort_key ||= 'updated_at' if sort_order == 'desc'
    sort_nulls = if sort_order == 'desc'
                   ' NULLS LAST'
                 else
                   ' NULLS FIRST'
                 end

    order_options = "#{sort_key} #{sort_order} #{sort_nulls}"

    # select percent
    select = '*'
    select_conditions = nil
    if sort_key == 'percent'
      select = '*, round(rectified_maps_count::float / maps_count::float * 100) as percent'
      select_conditions = 'maps_count > 0'
    end

    # pagination
    paginate_options = {
      page: index_params[:page],
      per_page: index_params[:per_page] || 50
    }

    # query
    query = index_params[:query]
    field = %w[name description].detect { |f| f == params[:field] }
    field ||= 'name'
    query_conditions = nil
    if query && query.strip.length > 0
      query = query.gsub(/\W/, ' ')
      query_conditions = ["#{field}  ~* ?", '(:punct:|^|)' + query + '([^A-z]|$)']
    end

    # bbox geo
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
                            Arel.sql("ST_Within(bbox_geom, ST_GeomFromText('#{bbox_polygon}'))")
                          else
                            Arel.sql("ST_Intersects(bbox_geom, ST_GeomFromText('#{bbox_polygon}'))")
                          end

        sort_geo = if params[:operation] == 'intersect'
                     Arel.sql("ABS(ST_Area(bbox_geom) - ST_Area(ST_GeomFromText('#{bbox_polygon}'))) ASC")
                   else
                     Arel.sql('ST_Area(bbox_geom) DESC')
                   end
      end

    end

    @layers = Layer.select(select).where(select_conditions).where(map_conditions).where(bbox_conditions).where(query_conditions).order(order_options).order(sort_geo).paginate(paginate_options)

    if request.format == 'geojson'
      render json: @layers, each_serializer: LayerGeoSerializer, adapter: :attributes
      return
    end

    render json: @layers, meta: {
      'total_entries' => @layers.total_entries,
      'total_pages' => @layers.total_pages
    }
  end

  def show
    if request.format == 'geojson'
      render json: @layer, serializer: LayerGeoSerializer, adapter: :attributes
      return
    end

    render json: @layer
  end

  def create
    @layer = Layer.new(layer_params)
    @layer.user = current_user

    if params[:data][:map_ids]
      selected_maps = Map.find(params[:data][:map_ids])
      selected_maps.each { |map| @layer.maps << map }
    end

    if @layer.save
      @layer.update_layer
      @layer.update_counts
      render json: @layer, status: :created
    else
      render json: @layer, status: :unprocessable_entity, serializer: ActiveModel::Serializer::ErrorSerializer
    end
  end

  def update
    if @layer.update(layer_params)
      if params[:data][:map_ids]
        selected_maps = Map.find(params[:data][:map_ids])
        selected_maps.each { |map| @layer.maps << map }
        @layer.update_layer
        @layer.update_counts
      end

      render json: @layer
    else
      render json: @layer, status: :unprocessable_entity, serializer: ActiveModel::Serializer::ErrorSerializer
    end
  end

  def destroy
    if @layer.destroy
      render json: @layer
    else
      render json: { errors: [{ title: 'Layer error', detail: 'Error deleting layer' }] },
             status: :unprocessable_entity
    end
  end

  # patch
  def toggle_visibility
    @layer.is_visible = !@layer.is_visible
    @layer.save
    @layer.update_layer

    render json: @layer
  end

  def remove_map
    map = Map.find(params[:map_id])

    if @layer.remove_map(map.id)
      render json: @layer
    else
      render json: { errors: [{ title: 'Layer error', detail: 'Error removing map.' }] },
             status: :unprocessable_entity
    end
  end

  # merge this layer with another one
  # moves all child object to new parent
  def merge
    dest_layer = Layer.find(params[:dest_id])
    if @layer.merge(dest_layer.id)
      render json: dest_layer
    else
      render json: { errors: [{ title: 'Layer error', detail: 'Error merging layers' }] },
             status: :unprocessable_entity
    end
  end

  # maps

  private

  def layer_params
    params.require(:data).require(:attributes).permit(:name, :description, :source_uri, :depicts_year)
  end

  def index_params
    params.permit(:page, :per_page, :query, :field, :sort_key, :sort_order, :field, :bbox, :operation, :format,
                  :map_id)
  end

  def find_layer
    @layer = Layer.find(params[:id])
  end

  def can_edit_layer
    return if current_user.present? && ((current_user == @layer.user) || current_user.has_role?('editor'))

    permission_denied
  end
end
