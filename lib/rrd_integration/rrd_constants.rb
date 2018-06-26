module RRDonnelley

  RRD_ASSETS_PATH_TEST = 'test/vendorImages'.freeze
  RRD_MECH_CHECK_PATH_TEST = 'test/vendorImagesXML_toMC'.freeze
  RRD_ASSET_UPDATE_PATH_TEST = 'test/vendorImagesXML_update'.freeze
  RRD_RESPONSE_PATH_TEST = 'test/vendorImages_RRDFeedback'.freeze
  RRD_HISTORY_PATH_TEST = 'test/vendorImages_history'.freeze
  RRD_SAMPLE_REQUEST_PATH_XML_TEST = 'XML_PhotoRequest'.freeze
  RRD_SAMPLE_REQUEST_PATH_EXCEL_TEST = 'Excel_PhotoRequest'.freeze
  RRD_SAMPLE_HISTORY_PATH_TEST = 'test/SampleHistoryFeed'.freeze

  RRD_ASSETS_PATH_PROD = 'vendorImages'.freeze
  RRD_MECH_CHECK_PATH_PROD = 'vendorImagesXML_toMC'.freeze
  RRD_ASSET_UPDATE_PATH_PROD = 'vendorImagesXML_update'.freeze
  RRD_RESPONSE_PATH_PROD = 'vendorImages_RRDFeedback'.freeze
  RRD_HISTORY_PATH_PROD = 'vendorImages_history'.freeze
  RRD_SAMPLE_REQUEST_PATH_XML_PROD = 'to_rrd'.freeze
  RRD_SAMPLE_REQUEST_PATH_EXCEL_PROD = 'Excel_PhotoRequest'.freeze
  RRD_SAMPLE_HISTORY_PATH_PROD = 'from_rrd'.freeze

  BELK_HEX_FEED_FTP_PATH_TEST = '../../../D/ecommercedev/colordata'.freeze
  BELK_HEX_FEED_FTP_PATH_PROD = '../../../D/ecommerce/colordata'.freeze
  BELK_ADS_FEED_FTP_PATH_TEST = '../../../D/ecommercedev/toCMP'.freeze
  BELK_ADS_FEED_FTP_PATH_PROD = '../../../D/ecommerce/toCMP'.freeze

  NUM_THREADS = 4.freeze
  TEMP_DIR = './tmp/rrd'.freeze
  TEMP_DIR_IMAGES = './tmp/rrd/images'.freeze
  TEMP_DIR_RESPONSES = './tmp/rrd/response_xml'.freeze
  TEMP_DIR_RESPONSES_MECH_CREATIVE_CHECK = './tmp/rrd/response_xml/mech_creative_check'.freeze
  TEMP_DIR_REQUESTS = './tmp/rrd/request_xml'.freeze
  TEMP_DIR_HISTORY = './tmp/rrd/history_xml'.freeze
  TEMP_DIR_SAMPLE_HISTORY = './tmp/rrd/sample_history_xml'.freeze
  TEMP_DIR_HEX_FEED = './tmp/hex_feed'.freeze
  TEMP_DIR_ADS_FEED = './tmp/ads_feed'.freeze
  BELK_EMAIL_GROUPS_FILEPATH_PROD = './lib/rrd_integration/cache/belk_email_groups_prod.json'.freeze
  BELK_EMAIL_GROUPS_FILEPATH_TEST = './lib/rrd_integration/cache/belk_email_groups_test.json'.freeze
  ADS_IMPORT_FILEPATH = './lib/rrd_integration/cache/ads_import.csv'.freeze
  ADS_FILES_MAX_NUM_TO_PROCESS = 8.freeze
  ADS_FEED_ERROR_EMAIL_RECIPIENTS = ['ecommitopssupport@belk.com', 'kari_newton@belk.com', 'Erin_Stevens@belk.com', 'lwheeler@salsify.com', 'kgaughan@salsify.com'].freeze

  S3_BUCKET_PROD = 'salsify-ce'.freeze
  S3_PATH_MECH_CREATIVE_CHECK_PROD = 'customers/belk/rrd/mech_creative_check'.freeze
  S3_PATH_IMAGE_HISTORIES_PROD = 'customers/belk/rrd/image_histories'.freeze
  S3_PATH_SAMPLE_HISTORIES_PROD = 'customers/belk/rrd/sample_histories'.freeze
  S3_PATH_ADS_FILES_PROD = 'customers/belk/ads_files'.freeze

  S3_BUCKET_TEST = 'salsify-ce'.freeze
  S3_PATH_MECH_CREATIVE_CHECK_TEST = 'customers/belk/test/rrd/mech_creative_check'.freeze
  S3_PATH_IMAGE_HISTORIES_TEST = 'customers/belk/test/rrd/image_histories'.freeze
  S3_PATH_SAMPLE_HISTORIES_TEST = 'customers/belk/test/rrd/sample_histories'.freeze
  S3_PATH_ADS_FILES_TEST = 'customers/belk/test/ads_files'.freeze

  # Exavault paths are accessed using Belk's user, so are relative to their base directory
  EXAVAULT_PATH_MECH_CREATIVE_CHECK_PROD = 'rrd/mech_creative_check'.freeze
  EXAVAULT_PATH_IMAGE_HISTORIES_PROD = 'rrd/image_histories'.freeze
  EXAVAULT_PATH_SAMPLE_HISTORIES_PROD = 'rrd/sample_histories'.freeze
  EXAVAULT_PATH_ADS_FILES_PROD = 'ads/ads_files'.freeze

  EXAVAULT_PATH_MECH_CREATIVE_CHECK_TEST = 'rrd/test/mech_creative_check'.freeze
  EXAVAULT_PATH_IMAGE_HISTORIES_TEST = 'rrd/test/image_histories'.freeze
  EXAVAULT_PATH_SAMPLE_HISTORIES_TEST = 'rrd/test/sample_histories'.freeze
  EXAVAULT_PATH_ADS_FILES_TEST = 'ads/test/ads_files'.freeze

  RRD_TASK_ID_PROPERTY = 'rrd_task_id'.freeze
  IPH_PATH_DELIMITER = '///'.freeze

  PROPERTY_PRODUCT_ID = 'product_id'.freeze
  PROPERTY_PARENT_PRODUCT = 'Parent Product'.freeze
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_IPH_CATEGORY = 'iphCategory'.freeze
  PROPERTY_HEX_COLOR = 'Hex Color'.freeze
  PROPERTY_VENDOR_NUMBER = 'Vendor#'.freeze
  PROPERTY_VENDOR_NAME = 'Vendor  Name'.freeze
  PROPERTY_STYLE_NUMBER = 'Style#'.freeze
  PROPERTY_BRAND = 'OmniChannel Brand'.freeze
  PROPERTY_DEPT_NUMBER = 'Dept#'.freeze
  PROPERTY_DEPT_NAME = 'Dept Description'.freeze
  PROPERTY_CLASS_NUMBER = 'Class#'.freeze
  PROPERTY_CLASS_NAME = 'Class Description'.freeze
  PROPERTY_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_OF_OR_SL = 'OForSL'.freeze
  PROPERTY_DISPLAY_NAME = 'Product Name'.freeze
  PROPERTY_COLOR_NAME = 'refinementColor'.freeze
  PROPERTY_GROUP_ORIN = 'Orin/Grouping #'.freeze
  PROPERTY_GROUPING_TYPE = 'groupingType'.freeze
  PROPERTY_SKU_ORIN = 'skuOrin'.freeze
  PROPERTY_TURN_IN_DATE = 'Turn-In Date'.freeze
  PROPERTY_COMPLETION_DATE = 'Completion Date'.freeze
  PROPERTY_SAMPLE_COMPLETE = 'Sample Coordinator Received Sample'.freeze
  PROPERTY_ALL_IMAGES = 'All Images'.freeze
  PROPERTY_REOPENED_REASON = 'Task Reopened Message'.freeze

  PROPERTY_WORKFLOW_ATTRIBUTE = 'ImageAssetSource'.freeze # This is a picklist and has values like Failed Mechanical Check, Initiated, ...
  # ^^^^ the below strings are in the picklist for this attribute as of 2017-07-08
  # Art Director Initiated
  # Awaiting New Vendor Image
  # Awaiting RRD Sample Photo
  # Completed
  # Failed Creative Check
  # Failed Mechanical Check
  # Image Asset with RRD
  # Image Task Assigned
  # Image Task Closed
  # Image Task Initiated
  # Image Task Ready for Aproval
  # Image Task Update Required
  # Image Upload Complete
  # Initiated
  # PDC Update Image
  # Pending Salsify to RRD upload
  # Ready for PIP
  # Ready to Review for AD
  # Received RRD Image for Sample
  # RRD Sample Photo Requested
  # Sample Management
  # Undoable Copy Task
  # Undoable Image Task
  # Uploaded Images
  # Vendor Provided Image
  # Waiting for Sample From Vendor
  PROPERTY_RRD_NOTES = 'RRD Notes'.freeze
  PROPERTY_RRD_IMAGE_ID = 'rrd_image_id'.freeze
  PROPERTY_IMAGE_METADATA = 'image_metadata'.freeze
  PROPERTY_SKU_IMAGES_UPDATED = 'sku_images_updated'.freeze
  PROPERTY_REJECTED_IMAGES = 'Vendor Images - RRD Rejected Images'.freeze
  PROPERTY_PIP_ALL_IMAGES_VERIFIED = 'PIP All Images Verified?'.freeze
  PROPERTY_PIP_IMAGE_APPROVED = 'PIP Image Approved?'.freeze
  PIP_WORKFLOW_STATUS = 'pip_workflow_status'.freeze
  REQUIRED_VEN_IMG_SHOT_TYPE = 'A'.freeze

  TIMEZONE_EST = 'Eastern Time (US & Canada)'.freeze

end
