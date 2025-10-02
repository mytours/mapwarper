module ApplicationHelper
  def admin_authorized?
    user_signed_in? && current_user.has_role?('administrator')
  end

  def editor_authorized?
    user_signed_in? && current_user.has_role?('editor')
  end

  FLASH_NOTICE_KEYS = %i[error notice warning alert]
  def flash_messages
    return unless messages = flash.keys.select { |k| FLASH_NOTICE_KEYS.include?(k.to_sym) }

    formatted_messages = messages.map do |type|
      content_tag :div, id: type.to_s do
        message_for_item(flash[type], flash[:"#{type}_item"])
      end
    end
    formatted_messages.join.html_safe
  end

  def message_for_item(message, item = nil)
    if item.is_a?(Array)
      raw message % link_to(*item)
    else
      message % item
    end
  end

  # from rails way
  def breadcrumbs(stop_at_controller = nil)
    return if %w[home my_maps].include?(controller.controller_name)

    html = [link_to(t('application.helper.breadcrumbs.home'), root_path)]
    # first level
    html << link_to(t('application.helper.breadcrumbs.search'), @link_back) if @link_back
    html << link_to(t('application.helper.breadcrumbs.maps'), maps_path) if @maps || @map
    if !(@layer || stop_at_controller) && @map
      html << link_to(t('application.helper.breadcrumbs.map', map_id: @map.id),
                      map_path(@map))
    end
    html << link_to(t('application.helper.breadcrumbs.map', map_id: @map.id), map_path(@map)) if @map && @layers

    # second level
    if @page && @page == 'for_map'
      html << link_to(t('application.helper.breadcrumbs.map_layers'), map_layers_path(@map))
    elsif @layers || @layer
      html << link_to(t('application.helper.breadcrumbs.layers'), layers_path)
    end

    if @layer && @layer.id
      html << link_to(t('application.helper.breadcrumbs.layer', layer_id: @layer.id),
                      layer_path(@layer))
    end
    html.join(' &gt; ').html_safe
  end

  def strip_brackets(str)
    str ||= ''
    str.gsub(/[\]\[()]/, '')
  end

  def snippet(thought, wordcount)
    return unless thought

    thought.split[0..(wordcount - 1)].join(' ') + (thought.split.size > wordcount ? '...' : '')
  end

  def snip_word(word, lettercount)
    return unless word

    word[0..lettercount - 1] + (word.size > lettercount ? '...' : '')
  end

  def assets(directory)
    assets = {}

    Rails.application.assets.index.each_logical_path("#{directory}/*") do |path|
      assets[path.sub(%r{^#{directory}/}, '')] = asset_path(path)
    end

    assets
  end

  def map_thumb_url(map)
    map.upload.url(:thumb)
  end

  def disabled_site?
    APP_CONFIG['disabled_site'] == true
  end
end
