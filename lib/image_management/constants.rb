module ImageManagement

  STAMP = '$IMAGE$'.freeze
  MAX_PRODUCTS_PER_CRUD = 100.freeze
  NUM_THREADS_CRUD = 8.freeze
  MAX_ASSETS_CRUD = 500.freeze

  TIMEZONE_EST = 'Eastern Time (US & Canada)'.freeze

  PROPERTY_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_COPY_APPROVAL_STATE = 'Copy Approval State'.freeze
  PROPERTY_GROUP_ORIN = 'Orin/Grouping #'.freeze
  PROPERTY_GROUPING_TYPE = 'groupingType'.freeze
  PROPERTY_IMAGE_METADATA = 'image_metadata'.freeze
  PROPERTY_IMAGE_TASK_MESSAGE = 'Image Specialist Task Message'.freeze
  PROPERTY_IMAGE_TASK_STATUS = 'Image Specialist Task Status'.freeze
  PROPERTY_IMAGE_TASK_COMPLETE = 'Image Specialist Task Complete'.freeze
  PROPERTY_PARENT_PRODUCT_ID = 'Parent Product'.freeze
  PROPERTY_PENDING_BASE_PUBLISH = 'isBasePublishPending'.freeze
  PROPERTY_PIP_ALL_IMAGES_VERIFIED = 'PIP All Images Verified?'.freeze
  PROPERTY_PIP_IMAGE_APPROVED = 'PIP Image Approved?'.freeze
  PROPERTY_PIP_WORKFLOW_STATUS = 'pip_workflow_status'.freeze
  PROPERTY_REOPENED_REASON = 'Task Reopened Message'.freeze
  PROPERTY_RRD_TASK_ID = 'rrd_task_id'.freeze
  PROPERTY_SKU_IMAGES_UPDATED = 'sku_images_updated'.freeze

  IMAGE_TASK_STATUS_COMPLETE = 'Complete'.freeze
  IMAGE_TASK_STATUS_REJECTED = 'Rejected'.freeze
  IMAGE_TASK_STATUS_REOPENED = 'ReOpen'.freeze

  PIP_WORKFLOW_STATUS_OPEN = 'Open'.freeze
  PIP_WORKFLOW_STATUS_CLOSED = 'Closed'.freeze
  PIP_WORKFLOW_STATUS_REOPEN = 'Re-open'.freeze

  PIP_TASK_MESSAGE_IMG_SPEC_COMPLETE = 'Task reopened on {{datetime}} because of completed image specialist task'.freeze

  BELK_IMAGE_UPLOAD_PATH_QA = '/D/ecommerce/Images/test/SalsifyVPI'.freeze
  BELK_IMAGE_UPLOAD_PATH_PROD = '/D/ecommerce/Images/Prod/SalsifyVPI'.freeze

end
