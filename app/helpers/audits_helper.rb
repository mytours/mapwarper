module AuditsHelper
  def formatted_action(action)
    action.gsub(/\W/, '').titleize
  end

  def summary(audit)
    summ = ''
    if audit.changes && audit.auditable_type == 'Map'
      changes = audit.audited_changes

      if changes && changes['status'] && changes['status'] != 'status'
        map_action = if changes['status'].class == Array && changes['status'][1]
                       Map::STATUS[changes['status'][1]]
                     elsif changes['status'].class == Integer
                       Map::STATUS[changes['status']]
                     else
                       :missing
                     end

        summ = case map_action
               when :unloaded
                 t('audits.helper.summary.unloaded')
               when :loading
                 t('audits.helper.summary.loading')
               when :available
                 t('audits.helper.summary.available')
               when :warping
                 t('audits.helper.summary.warping')
               when :warped
                 t('audits.helper.summary.warped')
               when :published
                 t('audits.helper.summary.published')
               else
                 ''
               end

      end # status

      if changes && changes['mask_status'] && changes['status'] != 'mask_status'

        if changes['mask_status'].class == Array && changes['mask_status'][1]
          mask_action = Map::MASK_STATUS[changes['mask_status'][1]]
        elsif changes['mask_status'].class == Integer
          Map::MASK_STATUS[changes['mask_status']]
        else
          mask_action = :missing
        end
        summ = case mask_action
               when :unmasked
                 t('audits.helper.summary.unmasked')
               when :masking
                 t('audits.helper.summary.masking')
               when :masked
                 t('audits.helper.summary.masked')
               else
                 ''
               end

      end # mask_status

    end # Map

    summ
  end
end
