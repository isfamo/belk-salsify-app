module Demandware

  MAX_PRODUCTS_PER_CRUD = 100.freeze
  MAX_TRIES_DATA_DICT = 4.freeze
  SLEEP_RETRY_DATA_DICT = 5.freeze
  MAX_WAIT_DATA_DICT = 7.freeze
  MAX_WAIT_ORG_ATTRS = 7.freeze
  SLEEP_TIME_IMPORT_QUEUE_FULL = 120.freeze

  DW_TYPE_SKU = '1_sku'.freeze
  DW_TYPE_MASTER = '2_master'.freeze
  DW_TYPE_IL = '3_il'.freeze
  DW_TYPE_COLLECTION = '4_collection'.freeze

  SALSIFY_TYPE_SKU = 'sku'.freeze
  SALSIFY_TYPE_BASE = 'base'.freeze
  SALSIFY_TYPE_GROUP_CPG = 'cpg'.freeze
  SALSIFY_TYPE_GROUP_SCG_SSG = 'scg_ssg'.freeze
  SALSIFY_TYPE_GROUP_COLLECTION = 'collection'.freeze
  GROUPING_TYPES_CPG = ['CPG'].freeze
  GROUPING_TYPES_SCG_SSG = ['SCG', 'SSG'].freeze
  GROUPING_TYPES_COLLECTION = ['RCG', 'BCG', 'GSG'].freeze
  GROUPING_TYPES_RCG = 'RCG'.freeze
  SALSIFY_TYPE_IL = 'il'.freeze

  DW_META_SOURCE_LEVEL = 'dw:source_level'.freeze
  DW_META_SOURCE_LEVEL_BASE = 'base'.freeze
  DW_META_SOURCE_LEVEL_SKU = 'sku'.freeze
  DW_META_XML_LEVEL = 'dw:xml_level'.freeze
  DW_META_XML_PATH = 'dw:xml_path'.freeze
  DW_META_PRIORITY = 'dw:priority'.freeze
  DW_META_FEED = 'dw:feed'.freeze
  DW_META_IS_CUSTOM_ATTRIBUTE = 'dw:is_custom_attribute'.freeze
  DW_META_TRANSFORM = 'dw:transform'.freeze
  DW_META_XML_PATH_DELIMITER = '/'.freeze
  DW_META_DELIMITER = '|'.freeze

  XML_MODE_MASTER = 'master'.freeze
  XML_MODE_LIMITED = 'limited'.freeze
  DW_CATALOG_ID_MASTER = 'belk-master-catalog'.freeze
  DW_CATALOG_ID_LIMITED = 'forte-master-catalog'.freeze

  PROPERTY_CHILD_SKUS_OF_GROUP = 'skus'.freeze
  PROPERTY_CHILD_STYLES_OF_GROUP = 'styles'.freeze
  PROPERTY_CLASS_NUMBER = 'Class#'.freeze
  PROPERTY_COLOR_COMPLETE = 'isColorComplete'.freeze
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_COPY_APPROVAL_STATE = 'Copy Approval State'.freeze
  PROPERTY_DEMAND_CTR = 'demandCtr'.freeze
  PROPERTY_DEPT_NAME = 'deptName'.freeze
  PROPERTY_DEPT_NUMBER = 'Dept#'.freeze
  PROPERTY_FLAG_GWP = 'GWP'.freeze
  PROPERTY_FLAG_PWP = 'PWP'.freeze
  PROPERTY_FLAG_PYG = 'PYG'.freeze
  PROPERTY_GIFT_CARD = 'Gift Card Only'.freeze
  PROPERTY_GROUP_ORIN = 'Orin/Grouping #'.freeze
  PROPERTY_GROUPING_TYPE = 'groupingType'.freeze
  PROPERTY_IL_ELIGIBLE = 'il_eligible'.freeze
  PROPERTY_IPH_CATEGORY = 'iphCategory'.freeze
  PROPERTY_ITEM_STATUS = 'Item Status'.freeze
  PROPERTY_LIMITED_CARE = 'Limited_Care'.freeze
  PROPERTY_LIMITED_CA_PROP_65 = 'Limited_CAProp65_Compliant'.freeze
  PROPERTY_LIMITED_COPY_PRODUCT_NAME = 'Limited_Copy_Product_Name'.freeze
  PROPERTY_LIMITED_COPY_PRODUCT_TEXT = 'Limited_Copy_Product_Text'.freeze
  PROPERTY_LIMITED_COUNTRY_OF_ORIGIN = 'Limited_Country_of_Origin'.freeze
  PROPERTY_LIMITED_EXCLUSIVE = 'Limited_Exclusive'.freeze
  PROPERTY_LIMITED_IMPORT_DOMESTIC = 'Limited_Import/Domestic'.freeze
  PROPERTY_LIMITED_MATERIAL = 'Limited_Material'.freeze
  PROPERTY_NRF_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_NRF_SIZE_CODE = 'nrfSizeCode'.freeze
  PROPERTY_OMNI_CHANNEL_BRAND = 'OmniChannel Brand'.freeze
  PROPERTY_OMNI_COLOR_DESC = 'omniChannelColorDescription'.freeze
  PROPERTY_OMNI_SIZE_DESC = 'omniSizeDesc'.freeze
  PROPERTY_PARENT_PRODUCT = 'Parent Product'.freeze
  PROPERTY_PENDING_BASE_PUBLISH = 'isBasePublishPending'.freeze
  PROPERTY_PIM_NRF_COLOR_CODE = 'PIM NRF Color Code'.freeze
  PROPERTY_PRODUCT_COPY_TEXT = 'Product Copy Text'.freeze
  PROPERTY_PRODUCT_ID = 'product_id'.freeze
  PROPERTY_READY_FOR_WEB = 'isReadyForWeb'.freeze
  PROPERTY_UPC = 'upc'.freeze
  PROPERTY_SCENE7_IMAGE_A = 'Scene7 Images - A - mainImage URL'.freeze
  PROPERTY_SCENE7_IMAGE_TLCA = 'Scene7 Images - TLCA - mainImage URL'.freeze
  PROPERTY_SENT_TO_DW_TIMESTAMP = 'sentToWebDate'.freeze
  PROPERTY_VENDOR_COLOR_DESC = 'vendorColorDescription'.freeze
  PROPERTY_VENDOR_SIZE_DESC = 'vendorSizeDescription'.freeze

  IPH_PATH_DELIMITER = '>'.freeze
  IPH_PATH_XML_DELIMITER = '///'.freeze

  BOOLEAN_PROPERTIES_DO_NOT_CONVERT = ['directShipFlag'].freeze

  OMNI_BRAND_LIMITED = 'THE LIMITED'.freeze

  PROPERTY_GROUP_PRODUCT_ATTRIBUTES = 'Product Attributes'.freeze

  ITEM_STATUS_INACTIVE = ['Delete', 'Deleted', 'Inactive', 'inactive'].freeze
  DEFAULT_TAX_CLASS_FOR_SKU = 'standard'.freeze
  DEFAULT_TAX_CLASS_FOR_MASTER = 'standard'.freeze
  DEFAULT_STEP_QUANTITY_FOR_SKU = '1'.freeze

  S3_BUCKET_PROD = 'salsify-ce'.freeze
  S3_BUCKET_TEST = 'salsify-ce'.freeze
  S3_KEY_UPDATED_PRODUCTS_JSON_PROD = 'customers/belk/demandware'.freeze
  S3_KEY_UPDATED_PRODUCTS_JSON_TEST = 'customers/belk/test/demandware'.freeze
  S3_KEY_UPDATED_PRODUCTS_JSON_DEV = 'customers/belk/test/demandware/dev'.freeze
  S3_KEY_UPDATED_PRODUCTS_JSON_ARCHIVE_PROD = 'customers/belk/demandware/archived'.freeze
  S3_KEY_UPDATED_PRODUCTS_JSON_ARCHIVE_TEST = 'customers/belk/test/demandware/archived'.freeze
  S3_KEY_CHANGES_TIMESTAMP_PROD = 'customers/belk/demandware/last_change_record_timestamp.txt'.freeze
  S3_KEY_CHANGES_TIMESTAMP_TEST = 'customers/belk/test/demandware/last_change_record_timestamp.txt'.freeze
  S3_KEY_DW_FEED_TIMESTAMP_PROD = 'customers/belk/demandware/last_dw_feed_timestamp.txt'.freeze
  S3_KEY_DW_FEED_TIMESTAMP_TEST = 'customers/belk/test/demandware/last_dw_feed_timestamp.txt'.freeze
  S3_KEY_DW_DAEMON_TIMESTAMP_PROD = 'customers/belk/demandware/last_dw_daemon_timestamp.txt'.freeze
  S3_KEY_DW_DAEMON_TIMESTAMP_TEST = 'customers/belk/test/demandware/last_dw_daemon_timestamp.txt'.freeze

  LOCAL_PATH_UPDATED_PRODUCTS_JSON = './tmp/dw_feed/dirty_products_json'.freeze
  FILENAME_UPDATED_PRODUCTS_JSON = 'belk_updated_families.json'.freeze

  LOCAL_PATH_DW_FEED_XMLS_DW = './tmp/dw_feed/generated_xml/dw'.freeze
  LOCAL_PATH_DW_FEED_XMLS_CFH = './tmp/dw_feed/generated_xml/cfh'.freeze
  LOCAL_PATH_DW_FEED_ZIPS_DW = './tmp/dw_feed/generated_zips/dw'.freeze
  LOCAL_PATH_DW_FEED_ZIPS_CFH = './tmp/dw_feed/generated_zips/cfh'.freeze

  LOCAL_PATH_PUBLISH_PENDING_IMPORT = './tmp/dw_feed/publish_pending_import'.freeze
  FILENAME_PUBLISH_PENDING_IMPORT = 'pending_skus.csv'.freeze
  FILENAME_PUBLISH_PENDING_IMPORT_LTD = 'pending_skus_limited.csv'.freeze

  LOCAL_PATH_SENT_TO_DW_IMPORT = './tmp/dw_feed/sent_to_dw_import'.freeze
  FILENAME_SENT_TO_DW_IMPORT = 'sent_to_dw_timestamp.csv'.freeze
  FILENAME_SENT_TO_DW_IMPORT_LTD = 'sent_to_dw_timestamp_limited.csv'.freeze

  TIMEZONE_EST = 'Eastern Time (US & Canada)'.freeze

  DW_XML_FIRST_LEVEL_ORDER = [
    'ean', 'upc', 'unit', 'min-order-quantity', 'step-quantity', 'display-name',
    'short-description', 'long-description', 'store-force-price-flag',
    'store-non-inventory-flag', 'store-non-revenue-flag', 'store-non-discountable-flag',
    'online-flag', 'available-flag', 'searchable-flag', 'images', 'tax-class-id', 'brand',
    'sitemap-included-flag', 'page-attributes', 'custom-attributes', 'product-set-products',
    'variations', 'pinterest-enabled-flag', 'facebook-enabled-flag', 'store-attributes'
  ].freeze

  DW_REQUIRED_PROPERTIES = [
    PROPERTY_PRODUCT_ID,
    PROPERTY_PARENT_PRODUCT,
    PROPERTY_ITEM_STATUS,
    PROPERTY_COLOR_MASTER,
    PROPERTY_NRF_COLOR_CODE,
    PROPERTY_GROUPING_TYPE,
    PROPERTY_CHILD_STYLES_OF_GROUP,
    PROPERTY_CHILD_SKUS_OF_GROUP,
    PROPERTY_IL_ELIGIBLE,
    PROPERTY_PENDING_BASE_PUBLISH,
    PROPERTY_SENT_TO_DW_TIMESTAMP,
    PROPERTY_PRODUCT_COPY_TEXT,
    PROPERTY_UPC,
    PROPERTY_FLAG_PWP,
    PROPERTY_FLAG_GWP,
    PROPERTY_FLAG_PYG,
    PROPERTY_OMNI_SIZE_DESC,
    PROPERTY_NRF_SIZE_CODE,
    PROPERTY_VENDOR_SIZE_DESC,
    PROPERTY_DEPT_NUMBER,
    PROPERTY_DEMAND_CTR,
    PROPERTY_GROUP_ORIN,
    PROPERTY_OMNI_COLOR_DESC,
    PROPERTY_VENDOR_COLOR_DESC,
    PROPERTY_IPH_CATEGORY,
    PROPERTY_GIFT_CARD,
    PROPERTY_COPY_APPROVAL_STATE,
    PROPERTY_SCENE7_IMAGE_A,
    PROPERTY_SCENE7_IMAGE_TLCA,
    PROPERTY_LIMITED_COPY_PRODUCT_NAME,
    PROPERTY_LIMITED_COPY_PRODUCT_TEXT,
    PROPERTY_LIMITED_CARE,
    PROPERTY_LIMITED_EXCLUSIVE,
    PROPERTY_LIMITED_IMPORT_DOMESTIC,
    PROPERTY_LIMITED_MATERIAL,
    PROPERTY_LIMITED_COUNTRY_OF_ORIGIN,
    PROPERTY_LIMITED_CA_PROP_65,
    PROPERTY_OMNI_CHANNEL_BRAND,
    'salsify:updated_at'
  ].freeze

  DW_EXPORT_PROPERTIES_TO_EXCLUDE = ['salsify:digital_assets'].freeze

end
