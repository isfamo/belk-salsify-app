Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html

  get '/auth/salsify/callback' => 'salsify_session#create'

  namespace 'api' do
    # CFH routes
    get 'categories', to: "categories#index"
    get 'refresh', to: "categories#refresh"
    get 'demand', to: "categories#demand"
    get 'full', to: "categories#full"
    get 'cma_on_demand', to: "cma_event#demand"
    post 'online_flag', to: "online_flag#create"
    get 'job_status', to: "job_statuses#index"

    # Image Management routes
    post 'img_properties_updated', to: "image#img_properties_updated"
    post 'image_specialist_task_complete', to: "image#image_specialist_task_complete"
    post 'image_specialist_task_reopened', to: "image#image_specialist_task_reopened"
    post 'rejection_notes_updated', to: "image#rejection_notes_updated"
    post 'start_sample_req', to: "image#start_sample_req"
    post 'pip_workflow_completed', to: "image#pip_workflow_completed"

    # RRD routes
    get 'bridge', to: "bridge#retrieve"
    post 'assets_deleted', to: "rrd#assets_deleted"
    get 'trigger_vendor_image_upload_job', to: "rrd#trigger_vendor_image_upload_job"
    get 'trigger_vendor_image_delete_job', to: "rrd#trigger_vendor_image_delete_job"
    get 'trigger_vendor_image_response_pull', to: "rrd#trigger_vendor_image_response_pull"
    get 'trigger_sample_request_job', to: "rrd#trigger_sample_request_job"
    get 'trigger_hex_feed', to: "rrd#trigger_hex_feed"
    get 'trigger_ads_feed', to: "rrd#trigger_ads_feed"
    get 'rrd_get_product', to: "rrd#get_product"
    post 'rrd_submit_requests', to: "rrd#submit_requests"
    post 'assign_new_task_id_to_parent', to: "rrd#assign_new_task_id_to_parent"
    post 'assign_new_task_id_to_product', to: "rrd#assign_new_task_id_to_product" # for when products make it through image approval process and don't already have a task id

    # Salsify to PIM routes
    post 'send_to_pim', to: "salsify_to_pim#send_to_pim"
    post 'set_default_sku', to: "salsify_to_pim#set_default_sku"
    # This one is just b/c going right to it crashes in papertrail, so this is to deal with that - must be a better way?
    #   or do we really just assume nobody will go there otherwise?
    get 'send_to_pim', to: "salsify_to_pim#send_to_pim_nope"

    # The Dirtifier - makes products show up as updated when their picklist values get updated (like "Jeans > Banana Bottoms" gets changed in the Properties to "Jeans > Apple Bottoms"
    #     everything that had been pointing to banana bottoms gets marked as changed)
    post 'dirty_product', to: "dirty_product#dirty_product"

    # Webhook that helps workflows
    post 'new_sample_flag', to: "new_sample_provided#new_sample_flag"
    post 'clear_copy_approval', to: "clear_copy_approval#clear_copy_approval"
    post 'clear_pip_image_approved', to: "clear_pip_image_approved#clear_pip_image_approved"

    # Color mapping auto-update routes
    post 'color_mapping_file_updated', to: "color_update#color_mapping_file_updated"
    post 'color_code_updated', to: "color_update#color_code_updated"
    post 'color_code_updated_non_master', to: "color_update#color_code_updated_non_master"
    post 'omni_color_updated', to: "color_update#omni_color_updated"

    # Department json file updated
    post 'department_config_file_updated', to: "rrd#department_config_file_updated"

    # Schema refresh route
    post 'refresh_attributes', to: "enrichment_attributes#refresh_attributes"

    # Enrichment lookup routes
    post 'set_initial_lookup_attributes', to: "enrichment_attributes#set_initial_lookup_attributes"

    # Demandware routes
    post 'demandware_publish', to: "demandware#publish"
    get 'test_demandware_publish', to: "demandware#test_publish"

    # New Product Grouping
    post 'new_product_grouping_ids', to: "new_product_grouping#generate_ids"
    post 'product_split_join', to: "new_product_grouping#recalculate_after_split_join"

    # Groupings
    post 'new_groupings', to: "groupings#new_groupings"
    post 'removed_groupings', to: "groupings#removed_groupings"
    post 'modified_groupings', to: "groupings#modified_groupings"

    # IPH added/changed
    post 'iph_change', to: "iph#iph_change"
    post 'sku_iph_change', to: "iph#sku_iph_change"
    post 'gxs_iph_config_updated', to: "iph#gxs_iph_config_updated"

    post 'il_sku_converted', to: "sku#il_sku_converted"
    post 'skus_created', to: "sku#skus_created"
    post 'color_master_deactivated', to: "sku#color_master_deactivated"

    namespace 'workhorse' do
      get 'sample_requests', to: 'workhorse#fetch_sample_requests'
      put 'sample_requests', to: 'workhorse#update_sample_requests'
    end
  end

  # XXX Angular routes -- these all need to be refactored since rails shouldn't
  # be aware of front end routing
  %w(tree cma status rrd rrd_print attribute_refresh).each do |route|
    get route, to: 'application#index'
  end

  get 'login', to: 'application#login'
  get 'logout', to: 'application#logout'

  root to: "application#index"
end
