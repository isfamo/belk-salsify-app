module Maintenance
  class ClearColorCodeLists
    include Muffin::SalsifyClient

    memoize_mode :off

    def self.run
      new.run
    end

    def run
      clear_cars_color_code_list
      clear_cfh_color_code_list
    end

    def clear_cars_color_code_list
      salsify_client(org_id: ENV.fetch('CARS_ORG_ID')).update_list(78695, clear_list_payload(78695))
    end

    def clear_cfh_color_code_list
      org_id = ProcessColorCodeFeed::ORG_ID
      list_id = ProcessColorCodeFeed::LIST_ID
      salsify_client(org_id: org_id).update_list(list_id, clear_list_payload(list_id))
    end

  end
end
