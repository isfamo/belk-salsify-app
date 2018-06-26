class ColorMasters

  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_DIGITAL_CONTENT_REQUIRED = 'digital_content_required'.freeze
  PROPERTY_ITEM_STATUS = 'Item Status'.freeze
  PROPERTY_NRF_COLOR_CODE = 'nrfColorCode'.freeze

  ITEM_STATUS_INACTIVE = ['Delete', 'Deleted', 'Inactive', 'inactive'].freeze

  # Calculate which skus should be changed to/from color masters.
  # Returns hash of proposed updates by product ID
  def self.evaluate_color_masters(style, skus)
    updates_by_product_id = {}
    skus.group_by { |sku| sku[PROPERTY_NRF_COLOR_CODE] }.each do |color_code, color_skus|

      color_masters = color_skus.select { |sku| sku[PROPERTY_COLOR_MASTER] }
      active_skus = color_skus.select do |sku|
        !ITEM_STATUS_INACTIVE.include?(sku[PROPERTY_ITEM_STATUS]) &&
        (
          sku[PROPERTY_DIGITAL_CONTENT_REQUIRED] == 'Y' || (
            [nil, ''].include?(sku[PROPERTY_DIGITAL_CONTENT_REQUIRED]) &&
            style[PROPERTY_DIGITAL_CONTENT_REQUIRED] == 'Y'
          )
        )
      end
      deactivated_color_masters, active_color_masters = color_masters.partition { |cm| ITEM_STATUS_INACTIVE.include?(cm[PROPERTY_ITEM_STATUS]) }

      # Mark all deactivated color masters as non master
      deactivated_color_masters.each do |color_master|
        updates_by_product_id[color_master['salsify:id']] ||= {}
        updates_by_product_id[color_master['salsify:id']][PROPERTY_COLOR_MASTER] = nil
      end

      if active_color_masters.length == 1 || active_skus.empty?
        # Good to go
      elsif active_color_masters.empty?
        # No color masters, pick one from among active skus
        updates_by_product_id[active_skus.first['salsify:id']] ||= {}
        updates_by_product_id[active_skus.first['salsify:id']][PROPERTY_COLOR_MASTER] = true
      else
        # Multiple color masters, mark all but one as non master
        active_color_masters[1..-1].each do |color_master|
          updates_by_product_id[color_master['salsify:id']] ||= {}
          updates_by_product_id[color_master['salsify:id']][PROPERTY_COLOR_MASTER] = nil
        end
      end

    end
    updates_by_product_id
  end

end
