module IphMapping

  STAMP = '$IPH_CHANGE$'.freeze

  IMPORT_FILE_LOCATION = './tmp/iph_mapping/imports'.freeze
  IMPORT_FILE_NAME = 'iph_mapping_import.json'.freeze
  IPH_CONFIG_FILE_LOCATION = './tmp/iph_mapping/config'.freeze
  IPH_CONFIG_FILE_NAME = 'gxs_iph_config.json'.freeze
  IPH_CONFIG_FILE_FTP_PATH_QA = './Customers/belk2/gxs_iph_config/QA/gxs_iph_config.json'.freeze
  IPH_CONFIG_FILE_FTP_PATH_PROD = './Customers/belk2/gxs_iph_config/PROD/gxs_iph_config.json'.freeze

  MAX_IDS_PER_FILTER = 100.freeze
  MAX_IDS_PER_CRUD = 100.freeze

  PROPERTY_IPH_CATEGORY = 'iphCategory'.freeze
  PROPERTY_PRODUCT_ID = 'product_id'.freeze
  PROPERTY_PARENT_PRODUCT_ID = 'Parent Product'.freeze
  PROPERTY_LAST_IPH_GXS_MAPPING = 'Last IPH GXS Mapping'.freeze
  PROPERTY_LAST_IPH_GXS_MAPPING_DATE = 'Last IPH GXS Mapping Date'.freeze
  PROPERTY_LAST_IPH_GXS_MAPPING_TIME = 'Last IPH GXS Mapping Time'.freeze
  PROPERTY_SKU_NEEDS_IPH_MAPPING = 'SKU Needs IPH Mapping'.freeze

end
